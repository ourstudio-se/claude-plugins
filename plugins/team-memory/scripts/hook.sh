#!/usr/bin/env bash
# Entry point for every team-memory hook: hook.sh <event>, hook input as JSON on stdin.
set -u

event="${1:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/settings.sh
. "$root/scripts/lib/settings.sh"
# shellcheck source=lib/repo.sh
. "$root/scripts/lib/repo.sh"
# shellcheck source=lib/index.sh
. "$root/scripts/lib/index.sh"
# shellcheck source=lib/scope.sh
. "$root/scripts/lib/scope.sh"
# shellcheck source=lib/secrets.sh
. "$root/scripts/lib/secrets.sh"
# shellcheck source=lib/memory.sh
. "$root/scripts/lib/memory.sh"
# shellcheck source=lib/write.sh
. "$root/scripts/lib/write.sh"

# A request from `team-memory pause|resume|undo` applies to the session whose hook sees it first.
REQUEST_MAX_AGE=120
# How long SessionStart waits for the pull before using the clone as it is.
SYNC_WAIT_SECONDS="${TEAM_MEMORY_SYNC_WAIT:-2}"

missing_tools() {
  local missing="" tool
  for tool in git gh jq curl; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    missing="$missing sha256sum"
  fi
  echo "${missing# }"
}

# Text for Claude is collected in $out and printed once at the end: plain stdout for SessionStart and
# UserPromptSubmit, JSON for the tool hooks.
out=""
say() {
  out="$out$1"$'\n'
}

flush() {
  [ -n "$out" ] || return 0
  case "$event" in
    SessionStart | UserPromptSubmit) printf '%s' "$out" ;;
    *) jq -n --arg e "$event" --arg m "${out%$'\n'}" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}' ;;
  esac
}

session_file() {
  echo "$(tm_state_dir)/sessions/$session.json"
}

session_get() {
  local f
  f=$(session_file)
  [ -f "$f" ] && jq -r "$@" "$f"
}

session_set() {
  local f tmp
  f=$(session_file)
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || echo '{}' >"$f"
  tmp="$f.tmp.$$"
  jq "$@" "$f" >"$tmp" && mv "$tmp" "$f"
}

# Tool hooks of one session can run in parallel; the session lock keeps their updates from overwriting each other.
session_lock() {
  local tries=0
  session_lock_dir="$(tm_state_dir)/sessions/$session.lock"
  mkdir -p "$(dirname "$session_lock_dir")"
  until mkdir "$session_lock_dir" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 50 ] || rm -rf "$session_lock_dir"
    sleep 0.05
  done
  trap 'rm -rf "$session_lock_dir"' EXIT
}

paused() {
  [ "$(session_get '.paused // false')" = "true" ]
}

team_active() {
  [ "$(session_get --arg t "$1" '.teams // {} | has($t)')" = "true" ]
}

apply_request() {
  local request action at arg
  request="$(tm_state_dir)/request"
  [ -f "$request" ] || return 0
  read -r action at arg <"$request"
  rm -f "$request"
  [ $(($(date +%s) - ${at:-0})) -le "$REQUEST_MAX_AGE" ] || return 0
  case "$action" in
    undo) undo_last_save ;;
    delete) delete_memory "$arg" ;;
    pause)
      session_set '.paused = true'
      say "team-memory: paused in this session. No team memory is loaded or saved until /team-memory resume."
      ;;
    resume)
      session_set '.paused = false'
      say "team-memory: resumed in this session."
      ;;
  esac
}

# start_sync <team>: pulls (or clones) the team's repo in the background and prints the pid.
start_sync() {
  local repo
  repo=$(jq -r --arg t "$1" '.teams[$t].repo' <<<"$settings")
  "$root/scripts/sync.sh" "$1" "$repo" </dev/null >/dev/null 2>&1 &
  echo $!
}

# wait_for <pids>: waits until they exit, at most SYNC_WAIT_SECONDS.
wait_for() {
  local tenths=0 pid running
  while [ "$tenths" -lt $((SYNC_WAIT_SECONDS * 10)) ]; do
    running=false
    for pid in "$@"; do
      kill -0 "$pid" 2>/dev/null && running=true
    done
    $running || return 0
    sleep 0.1
    tenths=$((tenths + 1))
  done
}

pull_due() {
  local last interval
  last=$(cat "$(tm_state_dir)/teams/$1/last_pull" 2>/dev/null || echo 0)
  interval=$(jq -r .pull_interval_minutes <<<"$settings")
  [ $(($(date +%s) - last)) -ge $((interval * 60)) ]
}

snapshot_file() {
  echo "$(tm_state_dir)/sessions/$session.$1.index"
}

cloned() {
  [ -d "$(tm_clones_dir)/$1/.git" ]
}

# All index lines for a team in this session: general/ plus the folder of each repo the session works in.
current_lines() {
  local key
  tm_general_index "$settings" "$1"
  for key in $(session_get --arg t "$1" '.teams[$t].repos[]?'); do
    tm_repo_index "$settings" "$1" "$key"
  done
}

show_notes() {
  local notes
  notes="$(tm_state_dir)/teams/$1/notes"
  [ -f "$notes" ] || return 0
  while IFS= read -r line; do
    say "team-memory: $line"
  done <"$notes"
  rm -f "$notes"
}

# show_index <team> <lines>: the team's header and index lines; records the lines as seen.
show_index() {
  local team="$1" lines="$2"
  say "# Team memory: $team"
  local clone guidelines
  clone="$(tm_clones_dir)/$team"
  say "Verified facts shared by team $team, from $clone. One line per memory; read the file when a line looks relevant to the task. When team memory and the user's personal memory disagree, personal memory wins."
  local rules
  rules=$(cat "$root/scripts/rules.md")
  rules="${rules//\{\{team\}\}/$team}"
  say "${rules//\{\{clone\}\}/$clone}"
  guidelines=$(jq -r '.guidelines // empty | if type == "array" then map("- " + .) | join("\n") else . end' "$clone/team-memory.json" 2>/dev/null)
  [ -z "$guidelines" ] || say "Team guidelines for $team:"$'\n'"$guidelines"
  if [ -n "$lines" ]; then
    say "$(printf '%s\n' "$lines" | sed 's/^#more /- /')"
  else
    say "(no memories yet)"
  fi
  printf '%s\n' "$lines" | grep -v '^#more ' >>"$(snapshot_file "$team")"
}

# activate <team> <signal> [<repo key>]: switches a team on mid-session, or adds a repo to an active team,
# and shows what is new: general/ when the team was off, plus the repo's folder.
activate() {
  local team="$1" signal="$2" key="${3:-}" was_active=false lines=""
  team_active "$team" && was_active=true
  if $was_active; then
    [ -n "$key" ] || return 0
    [ "$(session_get --arg t "$team" --arg k "$key" '.teams[$t].repos | index($k) != null')" = "false" ] || return 0
  fi
  session_set --arg t "$team" --arg s "$signal" --arg k "$key" \
    '.teams[$t] = ({signal: $s, repos: []} + (.teams[$t] // {})) | if $k != "" then .teams[$t].repos = (.teams[$t].repos + [$k] | unique) else . end'
  if ! cloned "$team"; then
    start_sync "$team" >/dev/null
    : >>"$(snapshot_file "$team")"
    $was_active || say "team-memory: the $team memory repo is being cloned; its index arrives with your next prompt."
    return 0
  fi
  $was_active || lines=$(tm_general_index "$settings" "$team")
  if [ -n "$key" ]; then
    lines=$(printf '%s\n%s' "$lines" "$(tm_repo_index "$settings" "$team" "$key")" | grep -v '^$')
  fi
  if $was_active; then
    [ -n "$lines" ] || return 0
    say "Team memory ($team) for $(tm_repo_folder "$key")/:"
    say "$lines"
    printf '%s\n' "$lines" >>"$(snapshot_file "$team")"
  else
    show_index "$team" "$lines"
  fi
}

# waiting_memories <repo key> <git root>: on the repo's default branch, reminds Claude of personal memories
# marked "Team memory after merge: <owner>/<repo>".
waiting_memories() {
  local key="$1" dir="$2" want branch default files
  want="${key#*/}"
  branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null) || return 0
  default=$(git -C "$dir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)
  default="${default#origin/}"
  if [ -z "$default" ]; then
    case "$branch" in main | master) default="$branch" ;; esac
  fi
  [ -n "$default" ] && [ "$branch" = "$default" ] || return 0
  files=$(grep -rlixF --include='*.md' -- "Team memory after merge: $want" "${TEAM_MEMORY_PERSONAL:-$HOME/.claude/projects}" 2>/dev/null | grep '/memory/[^/]*\.md$')
  [ -n "$files" ] || return 0
  say "Personal memories waiting for $want to reach $default, which this session is on:"
  say "$(printf '%s\n' "$files" | sed 's/^/- /')"
  say "Check each against the code here. Move the ones that are now true into team memory, without the marker line; after the save, run team-memory imported <personal file> <team memory file> and then remove the personal file and its MEMORY.md line. Leave the rest personal, and tell the user in one line what moved."
}

session_start() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      echo "team-memory: native Windows is not supported. Run Claude Code in WSL to use team memory."
      return
      ;;
  esac
  local missing team key cwd pids="" signal
  missing=$(missing_tools)
  if [ -n "$missing" ]; then
    echo "team-memory: off in this session, missing tools: $missing. Install them to use team memory."
    return
  fi
  paused && return
  find "$(tm_state_dir)/sessions" -type f -mtime +30 -delete 2>/dev/null

  for team in $(jq -r '.teams | to_entries[] | select(.value.enabled) | .key' <<<"$settings"); do
    if [ "$(git -C "$(tm_clones_dir)/$team" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" != "0" ]; then
      start_push "$team"
    else
      pids="$pids $(start_sync "$team")"
    fi
  done
  if [ -z "${TEAM_MEMORY_GH_LOGIN:-}" ] && [ ! -s "$(tm_state_dir)/gh-login" ] && command -v gh >/dev/null 2>&1; then
    (gh api user --jq .login >"$(tm_state_dir)/gh-login.tmp" 2>/dev/null && mv "$(tm_state_dir)/gh-login.tmp" "$(tm_state_dir)/gh-login") </dev/null >/dev/null 2>&1 &
  fi
  # TEAM_MEMORY_GITLEAKS points at a gitleaks the user manages; otherwise the pinned release is downloaded once.
  if [ -z "${TEAM_MEMORY_GITLEAKS:-}" ] && ! tm_gitleaks_available; then
    "$root/scripts/gitleaks.sh" </dev/null >/dev/null 2>&1 &
  fi

  cwd=$(jq -r '.cwd // ""' <<<"$input")
  session_set --arg c "$cwd" '.cwd = $c | .touched = (.touched // []) | .mcp = (.mcp // [])'
  key=""
  if root_dir=$(tm_git_root "$cwd"); then
    key=$(tm_cached_repo_key "$root_dir") || key=""
    [ -z "$key" ] || session_set --arg k "$key" '.touched = (.touched + [$k] | unique)'
  fi
  [ -z "$key" ] || for team in $(tm_teams_for_repo "$settings" "$key"); do
    session_set --arg t "$team" --arg s "repo $key" --arg k "$key" \
      '.teams[$t] = ({signal: $s, repos: []} + (.teams[$t] // {})) | .teams[$t].repos = (.teams[$t].repos + [$k] | unique)'
  done
  [ -n "$key" ] || for team in $(tm_workspace_teams "$settings" "$cwd"); do
    session_set --arg t "$team" '.teams[$t] = ({signal: "workspace", repos: []} + (.teams[$t] // {}))'
  done

  # Teams active from the start folder, plus those a resumed or compacted session activated earlier.
  local active
  active=$(session_get '.teams // {} | keys[]' | while read -r team; do
    jq -e --arg t "$team" '.teams[$t].enabled' <<<"$settings" >/dev/null 2>&1 && echo "$team"
  done)
  [ -n "$active" ] || return 0

  # shellcheck disable=SC2086
  wait_for $pids
  [ -z "$key" ] || waiting_memories "$key" "$root_dir"

  for team in $active; do
    show_notes "$team"
    : >"$(snapshot_file "$team")"
    if ! cloned "$team"; then
      say "team-memory: the $team memory repo is still being cloned; its index arrives with your next prompt."
      continue
    fi
    show_index "$team" "$(current_lines "$team")"
  done
}

user_prompt_submit() {
  local team snapshot lines new
  paused && return
  for team in $(session_get '.teams // {} | keys[]'); do
    jq -e --arg t "$team" '.teams[$t].enabled' <<<"$settings" >/dev/null 2>&1 || continue
    show_notes "$team"
    pull_due "$team" && start_sync "$team" >/dev/null
    cloned "$team" || continue
    snapshot=$(snapshot_file "$team")
    [ -f "$snapshot" ] || : >"$snapshot"
    lines=$(current_lines "$team" | grep -v '^#more ' || true)
    new=$(printf '%s\n' "$lines" | grep -vxF -f "$snapshot" | grep -v '^$' || true)
    [ -n "$new" ] || continue
    if [ -s "$snapshot" ]; then
      say "Team memory ($team) changed since you last saw its index; new or updated lines:"
      say "$new"
    else
      show_index "$team" "$lines"
    fi
    printf '%s\n' "$lines" >"$snapshot"
  done
}

# The signal of a tool call: the git root of the path it touched, or mcp:<server>.
tool_signal() {
  local p
  if [[ "$tool" == mcp__* ]]; then
    p="${tool#mcp__}"
    echo "mcp:${p%%__*}"
    return
  fi
  case "$tool" in
    Read | Write | Edit | MultiEdit) p="$tool_file" ;;
    Grep | Glob) p="${tool_path:-$tool_cwd}" ;;
    Bash) p="$tool_cwd" ;;
    *) return ;;
  esac
  [ -n "$p" ] || return
  case "$p" in
    /*) ;;
    *) p="$tool_cwd/$p" ;;
  esac
  case "$p" in
    "$clones" | "$clones"/*) return ;;
  esac
  tm_git_root "$p"
}

seen_file() {
  echo "$(tm_state_dir)/sessions/$session.seen"
}

# Records what a tool call touched and activates teams on its first signal.
post_tool_use() {
  local key team server
  paused && return
  case "$signal" in
    mcp:*)
      server="${signal#mcp:}"
      session_set --arg s "$server" '.mcp = ((.mcp // []) + [$s] | unique)'
      for team in $(jq -r --arg e "$signal" '.teams | to_entries[] | select(.value.enabled and (.value.scope | index($e))) | .key' <<<"$settings"); do
        activate "$team" "$signal"
      done
      ;;
    *)
      if team=$(tm_memory_repo_team "$settings" "$signal"); then
        # A copy of a team's memory repo is not work in a team repo.
        tm_register_copy "$signal" "$team"
      elif key=$(tm_cached_repo_key "$signal"); then
        session_set --arg k "$key" '.touched = ((.touched // []) + [$k] | unique)'
        for team in $(tm_teams_for_repo "$settings" "$key"); do
          activate "$team" "repo $key" "$key"
        done
        [ -z "$(tm_teams_for_repo "$settings" "$key")" ] || waiting_memories "$key" "$signal"
      else
        # A repo without a usable remote belongs to no team, so its paths count as foreign.
        session_set --arg r "$signal" '.local_roots = ((.local_roots // []) + [$r] | unique)'
      fi
      ;;
  esac
  echo "$signal" >>"$(seen_file)"
}

input=$(cat)

command -v jq >/dev/null 2>&1 || {
  [ "$event" = "SessionStart" ] && session_start
  exit 0
}

if [ "$event" = "PostToolUse" ]; then
  # Runs after most tool calls, so a call that brings nothing new exits before any further work.
  {
    read -r session
    read -r tool
    read -r tool_cwd
    read -r tool_file
    read -r tool_path
  } < <(jq -r '.session_id // "", .tool_name // "", .cwd // "", .tool_input.file_path // "", .tool_input.path // ""' <<<"$input" 2>/dev/null)
  tm_valid_session_id "${session:-}" || exit 0
  clones=$(tm_clones_dir)
  signal=$(tool_signal)
  memory_write=false
  case "$tool:$tool_file" in
    Write:"$clones"/* | Edit:"$clones"/* | MultiEdit:"$clones"/*) memory_write=true ;;
  esac
  if [ ! -f "$(tm_state_dir)/request" ] && ! $memory_write; then
    [ -n "$signal" ] || exit 0
    grep -qxF "$signal" "$(seen_file)" 2>/dev/null && exit 0
  fi
elif [ "$event" = "PreToolUse" ]; then
  # Runs before every edit and Bash command: anything that does not mention a team clone or a known copy of a
  # memory repo is allowed at once. A Write may create a file in a copy not seen yet, so it is always checked.
  relevant=false
  case "$input" in
    *"$(tm_clones_dir)"* | *".claude/team-memory"*) relevant=true ;;
  esac
  if ! $relevant; then
    while IFS= read -r copy; do
      [ -n "$copy" ] && [[ "$input" == *"$copy"* ]] && relevant=true && break
    done < <(tm_copy_roots)
  fi
  [[ "$input" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"Write\" ]] && relevant=true
  $relevant || exit 0
  session=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null)
  tm_valid_session_id "$session" || exit 0
else
  session=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null)
  tm_valid_session_id "$session" || exit 0
fi
settings=$(tm_settings_read 2>/dev/null) || exit 0

case "$event" in
  SessionStart)
    session_lock
    session_start
    ;;
  UserPromptSubmit)
    session_lock
    apply_request
    user_prompt_submit
    ;;
  PreToolUse) pre_tool_use ;;
  PostToolUse)
    session_lock
    apply_request
    [ -z "$signal" ] || post_tool_use
    if $memory_write; then
      post_memory_write
    fi
    ;;
  SessionEnd) session_end ;;
esac
flush
exit 0
