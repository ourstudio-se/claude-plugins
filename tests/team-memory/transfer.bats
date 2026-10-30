load helpers

setup_session() {
  export TEAM_MEMORY_BACKUP="$BATS_TEST_TMPDIR/backup"
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  CLONE="$TEAM_MEMORY_HOME/acme"
  PERSONAL="$HOME/.claude/projects/-home-test-projects/memory"
  mkdir -p "$PERSONAL"
  # Sessions of this personal memory folder started in acme/api.
  echo "{\"cwd\":\"$BATS_TEST_TMPDIR/projects/api\"}" >"$(dirname "$PERSONAL")/session.jsonl"
}

# personal_folder <name> <start folder or "">: a personal memory folder whose sessions started there.
personal_folder() {
  mkdir -p "$HOME/.claude/projects/$1/memory"
  [ -z "$2" ] || echo "{\"cwd\":\"$2\"}" >"$HOME/.claude/projects/$1/session.jsonl"
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

@test "moved-to-team refuses until the memory is pushed, then backs up and records the move" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  echo "personal version" >"$PERSONAL/project_kafka.md"
  echo "- [Kafka retries](project_kafka.md) — consumers retry three times" >"$PERSONAL/MEMORY.md"
  memory_text kafka-retries "Kafka consumers retry three times" >"$CLONE/general/kafka-retries.md"
  git -C "$CLONE" add general/kafka-retries.md
  git -C "$CLONE" commit -qm "memory: add general/kafka-retries.md"
  run tm moved-to-team "$PERSONAL/project_kafka.md" "$CLONE/general/kafka-retries.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not pushed yet"* ]]
  git -C "$CLONE" push -q
  run tm moved-to-team "$PERSONAL/project_kafka.md" "$CLONE/general/kafka-retries.md"
  [ "$status" -eq 0 ]
  backup=$(jq -r .backup "$TEAM_MEMORY_BACKUP/manifest.jsonl")
  [ "$(cat "$backup")" = "personal version" ]
  [ "$(jq -r .index_line "$TEAM_MEMORY_BACKUP/manifest.jsonl")" = "- [Kafka retries](project_kafka.md) — consumers retry three times" ]
  [ "$(jq -r .rel "$TEAM_MEMORY_BACKUP/manifest.jsonl")" = "general/kafka-retries.md" ]
}

@test "mine lists the user's own memories with where moved ones came from" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  save general/kafka-retries.md "Kafka consumers retry three times"
  wait_until remote_has "memory: add general/kafka-retries.md"
  echo "personal version" >"$PERSONAL/project_kafka.md"
  tm moved-to-team "$PERSONAL/project_kafka.md" "$CLONE/general/kafka-retries.md"
  git -C "$SEED" pull -q
  GIT_AUTHOR_EMAIL=colleague@example.com add_memory general/theirs.md "$(today)" "a colleague's memory"
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  run tm mine --json
  [ "$(jq -r 'map(.rel) | join(",")' <<<"$output")" = "general/es-error.md,repos/acme/api/retry.md,repos/acme/web/theme.md,general/kafka-retries.md" ]
  [ "$(jq -r '.[] | select(.rel == "general/kafka-retries.md") | .personal' <<<"$output")" = "$PERSONAL/project_kafka.md" ]
  [ "$(jq -r '.[] | select(.rel == "general/es-error.md") | .personal' <<<"$output")" = "null" ]
}

@test "teams remove --purge asks to keep the memories first when the user created memories" {
  setup_session
  run tm teams remove acme --purge
  [ "$status" -eq 1 ]
  [[ "$output" == *"restore-personal"* ]]
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

# moved <personal file name> <team rel> <description>: a personal memory moved to team memory through the hooks.
moved() {
  echo "original $1" >"$PERSONAL/$1"
  echo "- [$1]($1) — $3" >>"$PERSONAL/MEMORY.md"
  save "$2" "$3"
  wait_until remote_has "memory: add $2"
  tm moved-to-team "$PERSONAL/$1" "$CLONE/$2" >/dev/null
  rm "$PERSONAL/$1"
  grep -vF "($1)" "$PERSONAL/MEMORY.md" >"$PERSONAL/MEMORY.md.tmp" || true
  mv "$PERSONAL/MEMORY.md.tmp" "$PERSONAL/MEMORY.md"
}

@test "restore-personal refuses while the team is on, unless --yes" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  moved project_kafka.md general/kafka-retries.md "Kafka consumers retry three times"
  run tm restore-personal
  [ "$status" -eq 1 ]
  [[ "$output" == *"still on for acme"* ]]
  [ ! -f "$PERSONAL/project_kafka.md" ]
  run tm restore-personal --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$PERSONAL/project_kafka.md")" = "original project_kafka.md" ]
}

@test "restore-personal puts back the originals and their index lines, team memory untouched" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  moved project_kafka.md general/kafka-retries.md "Kafka consumers retry three times"
  moved project_es.md general/es-mapping.md "ES mapping"
  echo "kept" >"$PERSONAL/project_es.md"
  tm set acme.enabled false
  run tm restore-personal
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restored 1 personal memories"* ]]
  [[ "$output" == *"project_es.md (already exists"* ]]
  [ "$(cat "$PERSONAL/project_kafka.md")" = "original project_kafka.md" ]
  [ "$(cat "$PERSONAL/project_es.md")" = "kept" ]
  [ "$(grep -c '(project_kafka.md)' "$PERSONAL/MEMORY.md")" = "1" ]
  [ -f "$CLONE/general/kafka-retries.md" ]
  run tm restore-personal --force
  [ "$(cat "$PERSONAL/project_es.md")" = "original project_es.md" ]
  [ "$(grep -c '(project_kafka.md)' "$PERSONAL/MEMORY.md")" = "1" ]
}

@test "restore-personal with nothing moved says so" {
  setup_session
  run tm restore-personal
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to restore"* ]]
}

@test "personal-folders marks folders in and out of the team's scope" {
  setup_session
  repo_at hobby git@github.com:someone/hobby.git
  repo_at ws/web git@github.com:acme/web.git
  personal_folder hobby "$BATS_TEST_TMPDIR/hobby"
  personal_folder ws "$BATS_TEST_TMPDIR/ws"
  personal_folder gone "/no/such/folder"
  run tm personal-folders acme --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[] | select(.memory | contains("-home-test-projects")) | .scope' <<<"$output")" = "in" ]
  [ "$(jq -r '.[] | select(.memory | contains("/hobby/")) | .scope' <<<"$output")" = "out" ]
  [ "$(jq -r '.[] | select(.memory | contains("/ws/")) | .scope' <<<"$output")" = "in" ]
  [ "$(jq -r '.[] | select(.memory | contains("/gone/")) | .scope' <<<"$output")" = "unknown" ]
}

@test "a folder without transcripts is found from its name" {
  setup_session
  mkdir -p "$BATS_TEST_TMPDIR/projects/my-app.web"
  git init -q "$BATS_TEST_TMPDIR/projects/my-app.web"
  git -C "$BATS_TEST_TMPDIR/projects/my-app.web" remote add origin git@github.com:acme/my-app.web.git
  name=$(echo "$BATS_TEST_TMPDIR/projects/my-app.web" | tr '/.' '--')
  personal_folder "$name" ""
  run tm personal-folders acme
  [[ "$output" == *"in	$HOME/.claude/projects/$name/memory	$BATS_TEST_TMPDIR/projects/my-app.web"* ]]
}

@test "moved-to-team refuses a memory from outside the team's scope" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  repo_at hobby git@github.com:someone/hobby.git
  personal_folder hobby "$BATS_TEST_TMPDIR/hobby"
  echo "hobby fact" >"$HOME/.claude/projects/hobby/memory/fact.md"
  save general/kafka-retries.md "Kafka consumers retry three times"
  wait_until remote_has "memory: add general/kafka-retries.md"
  run tm moved-to-team "$HOME/.claude/projects/hobby/memory/fact.md" "$CLONE/general/kafka-retries.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside team acme's scope"* ]]
  [ -f "$HOME/.claude/projects/hobby/memory/fact.md" ]
}

@test "moved-to-team refuses a CLAUDE.md committed in a repo" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  echo "rule" >"$BATS_TEST_TMPDIR/projects/api/CLAUDE.md"
  git -C "$BATS_TEST_TMPDIR/projects/api" add CLAUDE.md
  git -C "$BATS_TEST_TMPDIR/projects/api" commit -qm claude
  save general/kafka-retries.md "Kafka consumers retry three times"
  wait_until remote_has "memory: add general/kafka-retries.md"
  run tm moved-to-team "$BATS_TEST_TMPDIR/projects/api/CLAUDE.md" "$CLONE/general/kafka-retries.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"committed in a repo"* ]]
}

@test "a file moved twice the same day keeps both backups and restores the original" {
  setup_session
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  echo "original" >"$PERSONAL/project_mixed.md"
  save general/first-part.md "first part"
  wait_until remote_has "memory: add general/first-part.md"
  tm moved-to-team "$PERSONAL/project_mixed.md" "$CLONE/general/first-part.md" >/dev/null
  echo "shortened" >"$PERSONAL/project_mixed.md"
  save general/second-part.md "second part"
  wait_until remote_has "memory: add general/second-part.md"
  tm moved-to-team "$PERSONAL/project_mixed.md" "$CLONE/general/second-part.md" >/dev/null
  [ "$(jq -sr 'map(.backup) | unique | length' "$TEAM_MEMORY_BACKUP/manifest.jsonl")" = "2" ]
  [ "$(cat "$(jq -sr '.[0].backup' "$TEAM_MEMORY_BACKUP/manifest.jsonl")")" = "original" ]
  [ "$(cat "$(jq -sr '.[1].backup' "$TEAM_MEMORY_BACKUP/manifest.jsonl")")" = "shortened" ]
  rm "$PERSONAL/project_mixed.md"
  tm set acme.enabled false
  tm restore-personal >/dev/null
  [ "$(cat "$PERSONAL/project_mixed.md")" = "original" ]
}
