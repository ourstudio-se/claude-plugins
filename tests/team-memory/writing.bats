load helpers

# An active session s1 in acme/api that has also touched a personal repo.
setup_session() {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  repo_at projects/hobby git@github.com:someone/hobby-tracker.git
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/hobby/main.go\"}" >/dev/null
  CLONE="$TEAM_MEMORY_HOME/acme"
}

# write_memory <session id> <relative path> <content>: the PreToolUse check, the write itself, then PostToolUse.
write_memory() {
  local file="$CLONE/$2" input
  input=$(jq -n --arg f "$file" --arg c "$3" '{file_path: $f, content: $c}')
  run pre_tool "$1" Write "$input"
  denied && return 0
  mkdir -p "$(dirname "$file")"
  printf '%s' "$3" >"$file"
  run post_tool "$1" Write "$input"
}

@test "a normal edit outside team memory is not checked" {
  setup_session
  run pre_tool s1 Edit "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/main.go\",\"old_string\":\"a\",\"new_string\":\"b\"}"
  [ -z "$output" ]
  run pre_tool s1 Bash '{"command":"rm -rf build"}'
  [ -z "$output" ]
}

@test "a valid memory is committed, pushed and announced with undo" {
  setup_session
  write_memory s1 general/kafka-retries.md "$(memory_text kafka-retries "Kafka consumers retry three times")"
  [[ "$(context)" == *"Saved to team memory (general): Kafka consumers retry three times · say \"undo\" to revert"* ]]
  [ "$(git -C "$CLONE" log -1 --format=%s)" = "memory: add general/kafka-retries.md" ]
  [ "$(git -C "$CLONE" log -1 --format=%ae)" = "test@example.com" ]
  wait_until remote_has "memory: add general/kafka-retries.md"
}

@test "a memory in the folder of a repo the session worked in is allowed" {
  setup_session
  write_memory s1 repos/acme/api/timeouts.md "$(memory_text timeouts "api times out after 30 s")"
  [[ "$(context)" == *"Saved to team memory (repos/acme/api)"* ]]
}

@test "a memory for a scope repo the session did not touch is refused" {
  setup_session
  write_memory s1 repos/acme/web/x.md "$(memory_text x "something")"
  denied
  [[ "$(reason)" == *"has not worked in acme/web"* ]]
  [[ "$(reason)" == *"repos/acme/api/"* ]]
  [ ! -f "$CLONE/repos/acme/web/x.md" ]
}

@test "writing is refused when the team is not active in the session" {
  setup_session
  session_start s2 "$BATS_TEST_TMPDIR/projects/hobby" >/dev/null
  write_memory s2 general/x.md "$(memory_text x "something")"
  denied
  [[ "$(reason)" == *"not active in this session"* ]]
}

@test "writing is refused while paused" {
  setup_session
  tm pause
  prompt s1
  write_memory s1 general/x.md "$(memory_text x "something")"
  denied
  [[ "$(reason)" == *"paused"* ]]
}

@test "a path outside general/ and repos/<owner>/<repo>/ is refused" {
  setup_session
  for rel in "x.md" "general/Bad_Name.md" "repos/acme/x.md" "general/sub/x.md" "team-memory.json"; do
    write_memory s1 "$rel" "$(memory_text x "something")"
    denied
  done
}

@test "a path inside a foreign repo the session touched is refused" {
  setup_session
  write_memory s1 general/x.md "$(memory_text x "fact" "Seen in $BATS_TEST_TMPDIR/projects/hobby/main.go")"
  denied
  [[ "$(reason)" == *"$BATS_TEST_TMPDIR/projects/hobby"* ]]
}

@test "a path inside a touched repo without a remote is refused" {
  setup_session
  mkdir -p "$BATS_TEST_TMPDIR/scratch"
  git init -q "$BATS_TEST_TMPDIR/scratch"
  post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/scratch/notes.txt\"}" >/dev/null
  write_memory s1 general/x.md "$(memory_text x "fact" "Found while testing in $BATS_TEST_TMPDIR/scratch")"
  denied
}

@test "naming a foreign repo is allowed unless its owner is private" {
  setup_session
  write_memory s1 general/lib.md "$(memory_text lib "someone/hobby-tracker has the same retry bug")"
  [[ "$(context)" == *"Saved to team memory"* ]]
  tm private add github.com/someone
  write_memory s1 general/lib2.md "$(memory_text lib2 "same retry bug as someone/hobby-tracker")"
  denied
  [[ "$(reason)" == *"someone/hobby-tracker"* ]]
}

@test "the user's own GitHub account counts as a private owner" {
  setup_session
  repo_at projects/mine git@github.com:test-user/side-project.git
  post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/mine/x.go\"}" >/dev/null
  write_memory s1 general/x.md "$(memory_text x "as in test-user/side-project")"
  denied
  write_memory s1 general/side.md "$(memory_text side "the word side-project alone is fine")"
  [[ "$(context)" == *"Saved to team memory"* ]]
}

@test "a secret is refused without repeating it" {
  setup_session
  token="ghp_abcdefghijklmnopqrstuvwxyz0123456789"
  write_memory s1 general/x.md "$(memory_text x "token handling" "Use $token to call the API")"
  denied
  [[ "$(reason)" == *"github-token"* ]]
  [[ "$(reason)" != *"$token"* ]]
  [ ! -f "$CLONE/general/x.md" ]
}

@test "the team's extra secret patterns are applied" {
  setup_session
  echo '{"secret_patterns": [{"name": "acme-key", "regex": "ACME-[0-9]{8}"}]}' >"$CLONE/team-memory.json"
  write_memory s1 general/x.md "$(memory_text x "key format" "The key ACME-12345678 is for prod")"
  denied
  [[ "$(reason)" == *"acme-key"* ]]
}

@test "an Edit is scanned on its new text" {
  setup_session
  run pre_tool s1 Edit "{\"file_path\":\"$CLONE/general/es-error.md\",\"old_string\":\"Body\",\"new_string\":\"password=hunter2hunter2\"}"
  denied
}

@test "invalid frontmatter is reported and not committed" {
  setup_session
  write_memory s1 general/x.md $'---\nname: wrong\ndescription: d\n---\nbody'
  [[ "$(context)" == *"Not saved to team memory yet"* ]]
  [[ "$(context)" == *"name must be \"x\""* ]]
  [[ "$(context)" == *"type must be project, reference or convention"* ]]
  [ "$(git -C "$CLONE" status --porcelain -- general/x.md)" = "?? general/x.md" ]
}

@test "editing an existing memory pulls it first" {
  setup_session
  printf -- '---\nname: es-error\ndescription: changed upstream\nmetadata:\n  type: project\n  date: %s\n---\nnew\n' "$(today)" >"$SEED/general/es-error.md"
  git -C "$SEED" commit -qam "upstream change"
  git -C "$SEED" push -q origin main
  run pre_tool s1 Edit "{\"file_path\":\"$CLONE/general/es-error.md\",\"old_string\":\"new\",\"new_string\":\"newer\"}"
  [ -z "$output" ]
  grep -q "changed upstream" "$CLONE/general/es-error.md"
}

@test "Bash may read team memory but not change it" {
  setup_session
  for cmd in "rm $CLONE/general/es-error.md" "echo x > $CLONE/general/x.md" "sed -i s/a/b/ ~/.claude/team-memory/acme/general/es-error.md" \
    "git -C $CLONE commit -am x" "cp /tmp/x $CLONE/general/" "find $CLONE -name '*.md' -delete"; do
    run pre_tool s1 Bash "$(jq -n --arg c "$cmd" '{command: $c}')"
    denied
  done
  for cmd in "cat $CLONE/general/es-error.md" "grep -r retries $CLONE 2>/dev/null" "ls ~/.claude/team-memory/acme/general" "git -C $CLONE log --oneline"; do
    run pre_tool s1 Bash "$(jq -n --arg c "$cmd" '{command: $c}')"
    [ -z "$output" ]
  done
}

@test "undo reverts the last save of the session and pushes the revert" {
  setup_session
  write_memory s1 general/kafka-retries.md "$(memory_text kafka-retries "Kafka consumers retry three times")"
  wait_until remote_has "memory: add general/kafka-retries.md"
  tm undo
  run post_tool s1 Bash '{"command":"team-memory undo"}' "$BATS_TEST_TMPDIR/projects/api"
  [[ "$(context)" == *"undone"* ]]
  [ ! -f "$CLONE/general/kafka-retries.md" ]
  wait_until remote_has 'Revert "memory: add general/kafka-retries.md"'
  tm undo
  run post_tool s1 Bash '{"command":"team-memory undo"}' "$BATS_TEST_TMPDIR/projects/api"
  [[ "$(context)" == *"nothing to undo"* ]]
}

@test "a push that races another push is rebased and retried" {
  setup_session
  add_memory general/other.md "$(today)" "someone else's memory"
  write_memory s1 general/mine.md "$(memory_text mine "my memory")"
  wait_until remote_has "memory: add general/mine.md"
  remote_has "add general/other.md"
}

@test "a real conflict keeps the local version on a pending branch and tells Claude" {
  setup_session
  printf -- '%s' "$(memory_text es-error "theirs")" >"$SEED/general/es-error.md"
  git -C "$SEED" commit -qam "their edit"
  git -C "$SEED" push -q origin main
  # The local edit happens without the pull that PreToolUse would do, as when two people save at the same moment.
  printf -- '%s' "$(memory_text es-error "mine")" >"$CLONE/general/es-error.md"
  run post_tool s1 Edit "{\"file_path\":\"$CLONE/general/es-error.md\",\"old_string\":\"a\",\"new_string\":\"b\"}"
  wait_until test -f "$TEAM_MEMORY_STATE/teams/acme/notes"
  [ -n "$(git -C "$CLONE" branch --list 'pending/*')" ]
  grep -q "description: theirs" "$CLONE/general/es-error.md"
  run prompt s1
  [[ "$output" == *"Conflict in general/es-error.md"* ]]
}

@test "offline: the commit stays local and is pushed at the next session start" {
  setup_session
  mv "$REMOTE" "$REMOTE.away"
  write_memory s1 general/offline.md "$(memory_text offline "saved while offline")"
  [[ "$(context)" == *"Saved to team memory"* ]]
  sleep 1
  mv "$REMOTE.away" "$REMOTE"
  session_start s2 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  wait_until remote_has "memory: add general/offline.md"
}

@test "SessionEnd pushes what is left" {
  setup_session
  printf -- '%s' "$(memory_text late "late fact")" >"$CLONE/general/late.md"
  git -C "$CLONE" add general/late.md
  git -C "$CLONE" commit -qm "memory: add general/late.md"
  hook SessionEnd '{"session_id":"s1","reason":"other"}'
  remote_has "memory: add general/late.md"
}

@test "team guidelines from team-memory.json are shown with the index" {
  setup_session
  echo '{"guidelines": ["Never save what is on the test branch only", "Link the PR"]}' >"$SEED/team-memory.json"
  git -C "$SEED" add team-memory.json
  git -C "$SEED" commit -qm guidelines
  git -C "$SEED" push -q origin main
  run session_start s3 "$BATS_TEST_TMPDIR/projects/api"
  [[ "$output" == *"Team guidelines for acme:"* ]]
  [[ "$output" == *"- Link the PR"* ]]
}
