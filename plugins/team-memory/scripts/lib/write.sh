# Saving memories: the checks before a write (PreToolUse), the commit after it (PostToolUse), undo and
# the final push (SessionEnd). Sourced by hook.sh and uses its globals and helpers.

# How long PreToolUse waits for a pull before an existing memory is edited.
EDIT_PULL_WAIT_SECONDS=3

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

bash_write_refused="Team memory files may only be changed with the Write or Edit tools, so the repo rule and the secret scan run. Bash may read them (cat, grep, ls, git log), but not change them."

# Bash may read team memory but never change it, so every change goes through the checks below.
guard_bash() {
  local cmd="$1" cwd="$2" clones copy mentioned=false inside=false
  clones=$(tm_clones_dir)
  case "$cmd" in
    *"$clones"* | *".claude/team-memory"*) mentioned=true ;;
  esac
  case "$cwd" in
    "$clones" | "$clones"/*) inside=true ;;
  esac
  while IFS= read -r copy; do
    [ -n "$copy" ] || continue
    [[ "$cmd" == *"$copy"* ]] && mentioned=true
    case "$cwd" in
      "$copy" | "$copy"/*) inside=true ;;
    esac
  done < <(tm_copy_roots)
  $mentioned || $inside || return 0
  local re
  for re in \
    '(^|[[:space:];&|(])(rm|mv|cp|tee|touch|mkdir|rmdir|ln|chmod|truncate|dd|install|rsync)[[:space:]]' \
    '(sed|perl)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i' \
    'git[[:space:]].*(add|commit|push|reset|checkout|rebase|revert|rm|mv|stash|clean|pull|merge|cherry-pick|restore|switch|apply|am|tag|branch)([[:space:]]|$)' \
    '(find|xargs).*(-delete|-exec|xargs)'; do
    [[ "$cmd" =~ $re ]] || continue
    deny "$bash_write_refused"
  done
  # A redirect into the team folder: the word after any > names it.
  local rest="$cmd" target
  while [[ "$rest" == *">"* ]]; do
    rest="${rest#*>}"
    target="${rest#"${rest%%[![:space:]>&|\"\']*}"}"
    target="${target%%[[:space:];&|]*}"
    case "$target" in
      /dev/*) ;;
      *"$clones"* | *".claude/team-memory"*) deny "$bash_write_refused" ;;
      /*) ;;
      ?*) $inside && deny "$bash_write_refused" ;;
    esac
  done
}

# The repo keys this session touched that are in the team's scope.
scope_repos() {
  session_get '.touched // [] | .[]' | while IFS= read -r key; do
    jq -e --arg t "$1" --arg o "${key%/*}" '.teams[$t].scope | index($o)' <<<"$settings" >/dev/null && echo "$key"
  done
}

# The repo keys this session touched that are outside the team's scope.
foreign_repos() {
  session_get '.touched // [] | .[]' | while IFS= read -r key; do
    jq -e --arg t "$1" --arg o "${key%/*}" '.teams[$t].scope | index($o)' <<<"$settings" >/dev/null || echo "$key"
  done
}

# private_owner <host/owner>: an owner whose repo names must not appear in team memory: the user's own
# GitHub account or an owner listed in private_owners.
private_owner() {
  [ "$1" = "github.com/$(gh_login)" ] && return 0
  jq -e --arg o "$1" '.private_owners | index($o)' <<<"$settings" >/dev/null
}

# The user's GitHub login, cached; TEAM_MEMORY_GH_LOGIN overrides it.
gh_login() {
  if [ -n "${TEAM_MEMORY_GH_LOGIN:-}" ]; then
    echo "$TEAM_MEMORY_GH_LOGIN"
  else
    cat "$(tm_state_dir)/gh-login" 2>/dev/null
  fi
}

# leak_in <team> <text file>: prints what the text names from foreign work in this session: a local path inside
# a foreign repo (or a repo without a remote), or the owner/repo of a repo with a private owner.
leak_in() {
  local key root
  for key in $(foreign_repos "$1"); do
    if private_owner "${key%/*}" && grep -qiF -- "${key#*/}" "$2"; then
      echo "${key#*/}"
      return
    fi
    for root in $(awk -F '\t' -v k="$key" '$2 == k { print $1 }' "$(tm_state_dir)/repo-keys" 2>/dev/null); do
      if grep -qF -- "$root" "$2"; then
        echo "$root"
        return
      fi
    done
  done
  for root in $(session_get '.local_roots // [] | .[]'); do
    if grep -qF -- "$root" "$2"; then
      echo "$root"
      return
    fi
  done
}

pre_tool_use() {
  local tool file parts team rel clone text allowed want found
  {
    read -r tool
    read -r file
  } < <(jq -r '.tool_name // "", .tool_input.file_path // ""' <<<"$input")
  if [ "$tool" = "Bash" ]; then
    guard_bash "$(jq -r '.tool_input.command // ""' <<<"$input")" "$(jq -r '.cwd // ""' <<<"$input")"
    return 0
  fi
  if ! parts=$(tm_memory_path "$file"); then
    local copy_root copy_team
    if copy_root=$(tm_git_root "$file") && copy_team=$(tm_memory_repo_team "$settings" "$copy_root"); then
      tm_register_copy "$copy_root" "$copy_team"
      deny "$copy_root is a copy of the $copy_team team memory repo, where changes skip the team memory checks. Edit team memory in $(tm_clones_dir)/$copy_team instead, where every save is checked and pushed."
    fi
    return 0
  fi
  team="${parts%% *}"
  rel="${parts#* }"
  clone="$(tm_clones_dir)/$team"

  tm_valid_memory_rel "$rel" ||
    deny "Team memories go in $clone/general/<slug>.md or $clone/repos/<owner>/<repo>/<slug>.md, with a slug of a-z, 0-9 and -."
  jq -e --arg t "$team" '.teams[$t].enabled' <<<"$settings" >/dev/null 2>&1 ||
    deny "$team is not an enabled team-memory team."
  paused && deny "Team memory is paused in this session. Save this as personal memory instead, or ask the user to run /team-memory resume."
  team_active "$team" ||
    deny "Team memory for $team is not active in this session, because the session has not worked in any of its repos. Save this as personal memory instead."

  if [[ "$rel" == repos/* ]]; then
    want=$(cut -d / -f 2-3 <<<"$rel")
    allowed=$(scope_repos "$team" | sed 's|^[^/]*/||')
    printf '%s\n' "$allowed" | grep -qxF -- "$want" ||
      deny "This session has not worked in $want, so the memory cannot go to repos/$want/. Use general/ for platform-wide facts, or the folder of a repo this session worked in: $(printf '%s\n' "$allowed" | grep -v '^$' | sed 's|^|repos/|; s|$|/|' | paste -sd ' ' -)"
  fi

  text=$(mktemp "${TMPDIR:-/tmp}/team-memory.XXXXXX")
  pre_text="$text"
  trap 'rm -f "$pre_text"' EXIT
  jq -r '.tool_input | (.content // ""), (.new_string // ""), ((.edits // [])[] | .new_string // "")' <<<"$input" >"$text"

  found=$(leak_in "$team" "$text")
  [ -z "$found" ] ||
    deny "The memory names \"$found\", which belongs to work outside team $team in this session. Remove it and keep only the team fact, or save this as personal memory."

  found=$(tm_scan_secrets "$text" "$clone/team-memory.json") ||
    deny "Possible secret found (rule: $(echo "$found" | tr '\n' ' ' | sed 's/ $//')). Remove it before saving: team memory is shared with everyone in $team and stays in git history."

  if [ -f "$file" ]; then
    # shellcheck disable=SC2046
    SYNC_WAIT_SECONDS=$EDIT_PULL_WAIT_SECONDS wait_for $(start_sync "$team")
  fi
}

# Commits a memory that was just written and pushes it in the background.
post_memory_write() {
  local parts team rel clone problems action sha description folder
  parts=$(tm_memory_path "$tool_file") || return 0
  team="${parts%% *}"
  rel="${parts#* }"
  clone="$(tm_clones_dir)/$team"
  tm_valid_memory_rel "$rel" && [ -d "$clone/.git" ] && [ -f "$tool_file" ] || return 0

  problems=$(tm_frontmatter_problems "$tool_file")
  if [ -n "$problems" ]; then
    say "Not saved to team memory yet, the frontmatter of $tool_file needs fixing:"
    say "$(echo "$problems" | sed 's/^/- /')"
    say "It is committed and pushed once it is valid."
    return 0
  fi

  if ! team_lock "$team"; then
    say "Not saved to team memory yet: the $team clone is busy with a pull or push. Save $rel again in a moment."
    return 0
  fi
  action=update
  git -C "$clone" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || action=add
  git -C "$clone" add -- "$rel"
  if git -C "$clone" diff --cached --quiet -- "$rel" || ! git -C "$clone" commit -q -m "memory: $action $rel" -- "$rel"; then
    team_unlock
    return 0
  fi
  sha=$(git -C "$clone" rev-parse HEAD)
  team_unlock
  session_set --arg t "$team" --arg s "$sha" --arg r "$rel" '.commits = ((.commits // []) + [{team: $t, sha: $s, rel: $r}])'
  start_push "$team"

  description=$(tm_frontmatter "$tool_file" | cut -f 2-)
  folder=$(dirname "$rel")
  say "Saved to team memory ($team): $rel, pushing in the background. Tell the user in one line: Saved to team memory ($folder): $description · say \"undo\" to revert"
}

# team_lock <team>: the clone lock shared with sync.sh and push.sh, waited for at most 8 s.
team_lock() {
  local tries=0
  team_lock_dir="$(tm_state_dir)/teams/$1/lock"
  mkdir -p "$(dirname "$team_lock_dir")"
  until mkdir "$team_lock_dir" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 80 ] || return 1
    sleep 0.1
  done
}

team_unlock() {
  rm -rf "$team_lock_dir"
}

start_push() {
  "$root/scripts/push.sh" "$1" </dev/null >/dev/null 2>&1 &
}

# delete_memory <file>: removes a team memory in a commit that undo can revert.
delete_memory() {
  local parts team rel clone description sha
  if ! parts=$(tm_memory_path "$1") || ! tm_valid_memory_rel "${parts#* }"; then
    say "team-memory: $1 is not a team memory file."
    return 0
  fi
  team="${parts%% *}"
  rel="${parts#* }"
  clone="$(tm_clones_dir)/$team"
  if ! team_active "$team" || paused; then
    say "team-memory: not deleted, team memory for $team is not active in this session."
    return 0
  fi
  if ! git -C "$clone" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    say "team-memory: not deleted, $rel is not in the $team memory repo."
    return 0
  fi
  description=$(tm_frontmatter "$clone/$rel" | cut -f 2-)
  if ! team_lock "$team"; then
    say "team-memory: not deleted yet, the $team clone is busy with a pull or push. Try again in a moment."
    return 0
  fi
  git -C "$clone" rm -q -- "$rel" && git -C "$clone" commit -q -m "memory: delete $rel" -- "$rel"
  sha=$(git -C "$clone" rev-parse HEAD)
  team_unlock
  session_set --arg t "$team" --arg s "$sha" --arg r "$rel" '.commits = ((.commits // []) + [{team: $t, sha: $s, rel: $r}])'
  start_push "$team"
  say "Deleted from team memory ($team): $rel. Tell the user in one line: Deleted from team memory ($(dirname "$rel")): $description · say \"undo\" to revert"
}

# Reverts the latest memory save of this session that is not undone yet.
undo_last_save() {
  local last team sha rel clone
  last=$(session_get '[.commits // [] | to_entries[] | select(.value.undone | not)] | last // empty | "\(.key) \(.value.team) \(.value.sha) \(.value.rel)"')
  if [ -z "$last" ]; then
    say "team-memory: nothing to undo, no team memory was saved in this session."
    return 0
  fi
  read -r index team sha rel <<<"$last"
  clone="$(tm_clones_dir)/$team"
  if ! team_lock "$team"; then
    say "team-memory: could not undo yet, the $team clone is busy with a pull or push. Try undo again in a moment."
    return 0
  fi
  if ! git -C "$clone" revert --no-edit "$sha" >/dev/null 2>&1; then
    git -C "$clone" revert --abort >/dev/null 2>&1
    team_unlock
    say "team-memory: could not undo the save of $rel, it was changed again afterwards. Edit or delete the memory instead."
    return 0
  fi
  team_unlock
  session_set --argjson i "$index" '.commits[$i].undone = true'
  start_push "$team"
  say "team-memory: undone, the save of $rel in team memory ($team) was reverted and the revert is being pushed. Tell the user in one line."
}

# Pushes what is left before the session ends; sandbox pods have no next session to retry in.
session_end() {
  local team
  for team in $(session_get '.teams // {} | keys[]'); do
    [ "$(git -C "$(tm_clones_dir)/$team" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" = "0" ] ||
      "$root/scripts/push.sh" "$team" </dev/null >/dev/null 2>&1
  done
}
