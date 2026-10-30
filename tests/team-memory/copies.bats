load helpers

# An active session in acme/api and a copy of the memory repo at $COPY, cloned like any other repo.
setup_copy() {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  COPY="$BATS_TEST_TMPDIR/projects/claude-team-memory"
  git clone -q "$REMOTE" "$COPY"
}

bash_in() {
  hook PreToolUse "$(jq -n --arg c "$2" --arg d "$1" '{session_id: "s1", cwd: $d, tool_name: "Bash", tool_input: {command: $c}}')"
}

@test "reading a copy does not count as work in a team repo" {
  setup_copy
  run post_tool s1 Read "{\"file_path\":\"$COPY/general/es-error.md\"}"
  [ -z "$output" ]
  [ "$(jq -r '.touched | join(",")' "$TEAM_MEMORY_STATE/sessions/s1.json")" = "github.com/acme/api" ]
  grep -qF "$COPY" "$TEAM_MEMORY_STATE/memory-copies"
}

@test "editing a file in a copy is refused and points to the plugin's clone" {
  setup_copy
  post_tool s1 Read "{\"file_path\":\"$COPY/general/es-error.md\"}" >/dev/null
  run pre_tool s1 Edit "{\"file_path\":\"$COPY/general/es-error.md\",\"old_string\":\"a\",\"new_string\":\"b\"}"
  denied
  [[ "$(reason)" == *"copy of the acme team memory repo"* ]]
  [[ "$(reason)" == *"$TEAM_MEMORY_HOME/acme"* ]]
}

@test "writing a new file in a copy not seen before is refused" {
  setup_copy
  run pre_tool s1 Write "{\"file_path\":\"$COPY/general/new.md\",\"content\":\"x\"}"
  denied
}

@test "a copy is recognised by its origin in another url form" {
  setup_copy
  tm teams add acme git@github.com:acme/claude-team-memory.git
  git -C "$COPY" remote set-url origin https://github.com/acme/claude-team-memory
  run pre_tool s1 Write "{\"file_path\":\"$COPY/general/new.md\",\"content\":\"x\"}"
  denied
}

@test "Bash may read a copy but not change it, also from inside it" {
  setup_copy
  post_tool s1 Read "{\"file_path\":\"$COPY/general/es-error.md\"}" >/dev/null
  for cmd in "git commit -am x" "git push" "echo x > general/x.md" "rm general/es-error.md"; do
    run bash_in "$COPY" "$cmd"
    denied
  done
  run bash_in "$HOME" "rm $COPY/general/es-error.md"
  denied
  for cmd in "git log --oneline" "cat general/es-error.md" "grep -r retries . 2>/dev/null" "ls > /dev/null"; do
    run bash_in "$COPY" "$cmd"
    [ -z "$output" ]
  done
}

@test "Bash may not commit from inside the plugin's own clone either" {
  setup_copy
  run bash_in "$TEAM_MEMORY_HOME/acme" "git commit -am x"
  denied
  run bash_in "$TEAM_MEMORY_HOME/acme" "git log --oneline"
  [ -z "$output" ]
}

@test "ordinary repos are unaffected" {
  setup_copy
  post_tool s1 Read "{\"file_path\":\"$COPY/general/es-error.md\"}" >/dev/null
  run pre_tool s1 Write "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/main.go\",\"content\":\"package main\"}"
  [ -z "$output" ]
  run bash_in "$BATS_TEST_TMPDIR/projects/api" "git commit -am x"
  [ -z "$output" ]
}
