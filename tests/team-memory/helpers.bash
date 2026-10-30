PLUGIN="$BATS_TEST_DIRNAME/../../plugins/team-memory"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export TEAM_MEMORY_SETTINGS="$BATS_TEST_TMPDIR/config/teams.json"
  export TEAM_MEMORY_STATE="$BATS_TEST_TMPDIR/state"
  export TEAM_MEMORY_HOME="$BATS_TEST_TMPDIR/clones"
  export TEAM_MEMORY_SYNC_WAIT=5
  # No gitleaks download in tests; the built-in patterns run.
  export TEAM_MEMORY_GITLEAKS="${TEAM_MEMORY_TEST_GITLEAKS:-$BATS_TEST_TMPDIR/no-gitleaks}"
  export TEAM_MEMORY_GH_LOGIN=test-user
  export GIT_CONFIG_NOSYSTEM=1
  git config --global init.defaultBranch main
  git config --global user.name "Test"
  git config --global user.email "test@example.com"
}

tm() {
  "$PLUGIN/bin/team-memory" "$@"
}

# hook <event> <json>
hook() {
  "$PLUGIN/scripts/hook.sh" "$1" <<<"$2"
}

setting() {
  jq -r "$1" "$TEAM_MEMORY_SETTINGS"
}

# A bare memory repo at $REMOTE with a working copy at $SEED for adding memories.
make_remote() {
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  SEED="$BATS_TEST_TMPDIR/seed"
  git init -q --bare "$REMOTE"
  git clone -q "$REMOTE" "$SEED" 2>/dev/null
  echo "# memory" >"$SEED/README.md"
  git -C "$SEED" add -A
  git -C "$SEED" commit -qm init
  git -C "$SEED" push -q origin main
}

# add_memory <path> <date> <description>
add_memory() {
  mkdir -p "$SEED/$(dirname "$1")"
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: project\n  date: %s\n---\n\nBody of %s.\n' \
    "$(basename "$1" .md)" "$3" "$2" "$1" >"$SEED/$1"
  git -C "$SEED" add -A
  git -C "$SEED" commit -qm "add $1"
  git -C "$SEED" push -q origin main
}

# A git repo at $WORK whose origin is <url>; nothing is ever fetched from it.
make_work_repo() {
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q "$WORK"
  git -C "$WORK" remote add origin "$1"
}

# A team "acme" with scope github.com/acme, using $REMOTE.
add_team() {
  tm teams add acme "$REMOTE" >/dev/null
  tm scope add acme github.com/acme >/dev/null
}

# session_start <session id> <cwd>
session_start() {
  hook SessionStart "{\"session_id\":\"$1\",\"cwd\":\"$2\",\"source\":\"startup\"}"
}

prompt() {
  hook UserPromptSubmit "{\"session_id\":\"$1\",\"prompt\":\"hi\"}"
}

today() {
  date +%Y-%m-%d
}

# post_tool <session id> <tool name> <tool_input json> [<cwd>]
post_tool() {
  hook PostToolUse "{\"session_id\":\"$1\",\"cwd\":\"${4:-$HOME}\",\"tool_name\":\"$2\",\"tool_input\":$3}"
}

context() {
  jq -r '.hookSpecificOutput.additionalContext' <<<"$output"
}

# A repo under $BATS_TEST_TMPDIR/<dir> with origin <url>.
repo_at() {
  mkdir -p "$BATS_TEST_TMPDIR/$1"
  git init -q "$BATS_TEST_TMPDIR/$1"
  git -C "$BATS_TEST_TMPDIR/$1" remote add origin "$2"
}

setup_team() {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_memory repos/acme/api/retry.md "$(today)" "api retries twice"
  add_memory repos/acme/web/theme.md "$(today)" "web theme gotcha"
  add_team
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
}

# pre_tool <session id> <tool name> <tool_input json>
pre_tool() {
  hook PreToolUse "{\"session_id\":\"$1\",\"cwd\":\"$HOME\",\"tool_name\":\"$2\",\"tool_input\":$3}"
}

denied() {
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
}

reason() {
  jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output"
}

# memory_text <slug> <description> [<body>]
memory_text() {
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: project\n  author: test@example.com\n  date: %s\n---\n\n%s\n' \
    "$1" "$2" "$(today)" "${3:-The fact. Source: https://github.com/acme/api/pull/1}"
}

# wait_until <command...>: retries for up to 5 s.
wait_until() {
  for _ in $(seq 50); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

remote_has() {
  git --git-dir="$REMOTE" log --format=%s main | grep -qF -- "$1"
}
