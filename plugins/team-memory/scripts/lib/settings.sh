# Settings, state and clone locations, sourced by bin/team-memory and scripts/hook.sh.
# Bash 3.2 compatible; JSON is handled with jq.

TM_DEFAULTS='{"pull_interval_minutes":5,"stale_after_months":6,"max_general_index_lines":900,"max_repo_index_lines":600,"private_owners":[],"teams":{}}'

# TEAM_MEMORY_SETTINGS, TEAM_MEMORY_STATE and TEAM_MEMORY_HOME override the locations (used by tests).
tm_settings_path() {
  local p="${TEAM_MEMORY_SETTINGS:-${CLAUDE_PLUGIN_OPTION_SETTINGS_PATH:-$HOME/.config/claude-team-memory/teams.json}}"
  case "$p" in
    "~/"*) p="$HOME/${p#"~/"}" ;;
  esac
  echo "$p"
}

tm_state_dir() {
  echo "${TEAM_MEMORY_STATE:-$HOME/.cache/claude-team-memory}"
}

tm_clones_dir() {
  echo "${TEAM_MEMORY_HOME:-$HOME/.claude/team-memory}"
}

# Backups of imported personal memories and the manifest of what moved where, kept so they can be restored.
tm_backup_dir() {
  echo "${TEAM_MEMORY_BACKUP:-$HOME/.claude/team-memory-backup}"
}

tm_die() {
  echo "team-memory: $*" >&2
  exit 1
}

# Prints the settings with defaults filled in.
tm_settings_read() {
  local f
  f=$(tm_settings_path)
  if [ ! -f "$f" ]; then
    echo "$TM_DEFAULTS"
    return
  fi
  jq --argjson d "$TM_DEFAULTS" '$d * .' "$f" 2>/dev/null || tm_die "$f is not valid JSON"
}

# tm_settings_update [jq options...] <filter>: applies the filter and writes the file atomically.
tm_settings_update() {
  local f current updated tmp
  f=$(tm_settings_path)
  current=$(tm_settings_read) || exit 1
  updated=$(jq "$@" <<<"$current") || tm_die "could not update settings"
  mkdir -p "$(dirname "$f")"
  tmp="$f.tmp.$$"
  printf '%s\n' "$updated" >"$tmp" && mv "$tmp" "$f"
}

tm_valid_team_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

# A scope entry is <git host>/<owner> or mcp:<server>.
tm_valid_scope_entry() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]+/[A-Za-z0-9_.-]+$ ]] || [[ "$1" =~ ^mcp:[A-Za-z0-9_.-]+$ ]]
}

tm_valid_session_id() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}
