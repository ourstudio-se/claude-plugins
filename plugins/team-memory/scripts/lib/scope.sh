# Finding the repo behind a path, cached, and detecting workspace folders.

# tm_git_root <path>: the nearest folder at or above path that holds .git. The path may not exist yet.
tm_git_root() {
  local d="${1%/}"
  while [ -n "$d" ] && [ ! -d "$d" ]; do
    d="${d%/*}"
  done
  while [ -n "$d" ]; do
    [ -e "$d/.git" ] && echo "$d" && return 0
    d="${d%/*}"
  done
  return 1
}

# tm_cached_repo_key <git root>: the repo key, looked up once per root and cached ("-" for no usable origin).
tm_cached_repo_key() {
  local cache key
  cache="$(tm_state_dir)/repo-keys"
  key=$(awk -F '\t' -v r="$1" '$1 == r { print $2; exit }' "$cache" 2>/dev/null)
  if [ -z "$key" ]; then
    key=$(tm_repo_key "$1" 2>/dev/null) || key="-"
    mkdir -p "$(dirname "$cache")"
    printf '%s\t%s\n' "$1" "$key" >>"$cache"
  fi
  [ "$key" != "-" ] && echo "$key"
}

# tm_workspace_teams <settings json> <dir>: teams for which dir is a workspace folder: not a git repo itself,
# with at least one direct subfolder in the team's scope and none from an owner outside it.
tm_workspace_teams() {
  local settings="$1" dir="$2" sub key owners=""
  [ -e "$dir/.git" ] && return 0
  for sub in "$dir"/*/; do
    [ -e "$sub.git" ] || continue
    key=$(tm_cached_repo_key "${sub%/}") || continue
    owners="$owners${key%/*}"$'\n'
  done
  [ -n "$owners" ] || return 0
  jq -r --arg o "$owners" '
    ($o | split("\n") | map(select(. != "")) | unique) as $owners
    | .teams | to_entries[]
    | select(.value.enabled and .value.workspace_detection)
    | . as $team
    | select(all($owners[]; . as $owner | $team.value.scope | index($owner)))
    | .key' <<<"$settings"
}
