load helpers

setup_session() {
  export TEAM_MEMORY_BACKUP="$BATS_TEST_TMPDIR/backup"
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  CLONE="$TEAM_MEMORY_HOME/acme"
  PERSONAL="$HOME/.claude/projects/-home-test-projects/memory"
  mkdir -p "$PERSONAL"
}

# save <relative path> <description>: a memory saved through the hooks in session s1.
save() {
  local input
  input=$(jq -n --arg f "$CLONE/$1" --arg c "$(memory_text "$(basename "$1" .md)" "$2")" '{file_path: $f, content: $c}')
  pre_tool s1 Write "$input" >/dev/null
  mkdir -p "$(dirname "$CLONE/$1")"
  memory_text "$(basename "$1" .md)" "$2" >"$CLONE/$1"
  post_tool s1 Write "$input" >/dev/null
}

@test "the full writing rules are injected with the clone path filled in" {
  setup_session
  run session_start s1 "$BATS_TEST_TMPDIR/projects/api"
  [[ "$output" == *"## Saving to team memory (acme)"* ]]
  [[ "$output" == *"$CLONE/general/<slug>.md"* ]]
  [[ "$output" != *"{{"* ]]
}

@test "delete removes a memory in a commit that undo reverts" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  tm delete "$CLONE/general/es-error.md"
  run post_tool s1 Bash '{"command":"team-memory delete"}' "$BATS_TEST_TMPDIR/projects/api"
  [[ "$(context)" == *"Deleted from team memory (general): ES rejects string error fields · say \"undo\" to revert"* ]]
  [ ! -f "$CLONE/general/es-error.md" ]
  wait_until remote_has "memory: delete general/es-error.md"
  tm undo
  run post_tool s1 Bash '{"command":"team-memory undo"}' "$BATS_TEST_TMPDIR/projects/api"
  [ -f "$CLONE/general/es-error.md" ]
}

@test "delete is refused when the team is not active" {
  setup_session
  tm delete "$CLONE/general/es-error.md"
  run post_tool s1 Bash '{"command":"team-memory delete"}' "$HOME"
  [[ "$(context)" == *"not active in this session"* ]]
  [ -f "$CLONE/general/es-error.md" ]
}

@test "imported refuses until the memory is pushed, then backs up and records the move" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  echo "personal version" >"$PERSONAL/project_kafka.md"
  echo "- [Kafka retries](project_kafka.md) — consumers retry three times" >"$PERSONAL/MEMORY.md"
  memory_text kafka-retries "Kafka consumers retry three times" >"$CLONE/general/kafka-retries.md"
  git -C "$CLONE" add general/kafka-retries.md
  git -C "$CLONE" commit -qm "memory: add general/kafka-retries.md"
  run tm imported "$PERSONAL/project_kafka.md" "$CLONE/general/kafka-retries.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not pushed yet"* ]]
  git -C "$CLONE" push -q
  run tm imported "$PERSONAL/project_kafka.md" "$CLONE/general/kafka-retries.md"
  [ "$status" -eq 0 ]
  backup=$(jq -r .backup "$TEAM_MEMORY_BACKUP/manifest.jsonl")
  [ "$(cat "$backup")" = "personal version" ]
  [ "$(jq -r .index_line "$TEAM_MEMORY_BACKUP/manifest.jsonl")" = "- [Kafka retries](project_kafka.md) — consumers retry three times" ]
  [ "$(jq -r .rel "$TEAM_MEMORY_BACKUP/manifest.jsonl")" = "general/kafka-retries.md" ]
}

@test "mine lists the user's own memories with where imported ones came from" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  save general/kafka-retries.md "Kafka consumers retry three times"
  wait_until remote_has "memory: add general/kafka-retries.md"
  echo "personal version" >"$PERSONAL/project_kafka.md"
  tm imported "$PERSONAL/project_kafka.md" "$CLONE/general/kafka-retries.md"
  git -C "$SEED" pull -q
  GIT_AUTHOR_EMAIL=colleague@example.com add_memory general/theirs.md "$(today)" "a colleague's memory"
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  run tm mine --json
  [ "$(jq -r 'map(.rel) | join(",")' <<<"$output")" = "general/es-error.md,repos/acme/api/retry.md,repos/acme/web/theme.md,general/kafka-retries.md" ]
  [ "$(jq -r '.[] | select(.rel == "general/kafka-retries.md") | .personal' <<<"$output")" = "$PERSONAL/project_kafka.md" ]
  [ "$(jq -r '.[] | select(.rel == "general/es-error.md") | .personal' <<<"$output")" = "null" ]
}

@test "teams remove --purge asks for an export first when the user created memories" {
  setup_session
  run tm teams remove acme --purge
  [ "$status" -eq 1 ]
  [[ "$output" == *"/team-memory-export"* ]]
  [ -d "$CLONE" ]
  run tm teams remove acme --purge --yes
  [ "$status" -eq 0 ]
  [ ! -d "$CLONE" ]
}

# waiting <file name> <repo>: a personal memory marked for team memory after <repo> is merged.
waiting() {
  printf -- '---\nname: x\ndescription: new flag\n---\nThe new flag.\n\nTeam memory after merge: %s\n' "$2" >"$PERSONAL/$1"
}

@test "personal memories waiting for a repo are shown on its default branch" {
  setup_session
  waiting project_flag.md acme/api
  waiting project_other.md acme/web
  run session_start s1 "$BATS_TEST_TMPDIR/projects/api"
  [[ "$output" == *"Personal memories waiting for acme/api to reach main"* ]]
  [[ "$output" == *"- $PERSONAL/project_flag.md"* ]]
  [[ "$output" != *"project_other.md"* ]]
}

@test "nothing is shown on a feature branch" {
  setup_session
  waiting project_flag.md acme/api
  git -C "$BATS_TEST_TMPDIR/projects/api" checkout -q -b feature/flag
  run session_start s1 "$BATS_TEST_TMPDIR/projects/api"
  [[ "$output" != *"waiting for"* ]]
}

@test "the reminder also comes when the repo is first touched mid-session" {
  setup_session
  waiting project_flag.md acme/api
  session_start s1 "$HOME" >/dev/null
  run post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/x.go\"}"
  [[ "$(context)" == *"Personal memories waiting for acme/api"* ]]
}

@test "the remote's default branch is used when it is known" {
  setup_session
  waiting project_flag.md acme/api
  api="$BATS_TEST_TMPDIR/projects/api"
  git -C "$api" commit -q --allow-empty -m init
  git -C "$api" branch -q -m develop
  git -C "$api" update-ref refs/remotes/origin/develop HEAD
  git -C "$api" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
  run session_start s1 "$api"
  [[ "$output" == *"waiting for acme/api to reach develop"* ]]
}
