# Repo keys and team activation. A repo key is <host>/<owner>/<repo>, taken from the origin remote.

# tm_repo_url_key <url>: git@github.com:o/r.git, https://github.com/o/r and ssh://git@github.com/o/r.git all give github.com/o/r.
tm_repo_url_key() {
  local u="$1" host
  u="${u%/}"
  u="${u%.git}"
  case "$u" in
    *://*)
      u="${u#*://}"
      u="${u#*@}"
      host="${u%%/*}"
      u="${host%%:*}/${u#*/}"
      ;;
    *:*)
      u="${u#*@}"
      u="${u/://}"
      ;;
    *) return 1 ;;
  esac
  host=$(echo "${u%%/*}" | tr '[:upper:]' '[:lower:]')
  u="$host/${u#*/}"
  [[ "$u" =~ ^[a-z0-9.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$ ]] || return 1
  echo "$u"
}

# tm_repo_key <dir>: the repo key of the git repo that contains dir.
tm_repo_key() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  tm_repo_url_key "$url"
}

# tm_repo_folder <repo key>: the memory folder for a repo, repos/<owner>/<repo>.
tm_repo_folder() {
  echo "repos/${1#*/}"
}

# tm_teams_for_repo <settings json> <repo key>: enabled teams whose scope holds the repo's <host>/<owner>.
tm_teams_for_repo() {
  jq -r --arg o "${2%/*}" '.teams | to_entries[] | select(.value.enabled and (.value.scope | index($o))) | .key' <<<"$1"
}
