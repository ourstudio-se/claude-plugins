load helpers

@test "reading a file in a scope repo activates the team mid-session" {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  run session_start s1 "$HOME"
  [ -z "$output" ]
  run post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/src/main.go\"}"
  [ "$status" -eq 0 ]
  [[ "$(context)" == *"# Team memory: acme"* ]]
  [[ "$(context)" == *"general/es-error.md"* ]]
  [[ "$(context)" == *"repos/acme/api/retry.md"* ]]
  [[ "$(context)" != *"theme"* ]]
  run post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/README.md\"}"
  [ -z "$output" ]
  run prompt s1
  [ -z "$output" ]
}

@test "a second scope repo adds only its own lines" {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  repo_at projects/web https://github.com/acme/web.git
  session_start s1 "$BATS_TEST_TMPDIR/projects/api"
  run post_tool s1 Grep "{\"pattern\":\"x\",\"path\":\"$BATS_TEST_TMPDIR/projects/web\"}"
  [ "$(context)" = "Team memory (acme) for repos/acme/web/:
- repos/acme/web/theme.md: web theme gotcha" ]
}

@test "a Bash command activates through its working directory" {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  run post_tool s1 Bash '{"command":"go test ./..."}' "$BATS_TEST_TMPDIR/projects/api"
  [[ "$(context)" == *"repos/acme/api/retry.md"* ]]
}

@test "a relative path is resolved against the working directory" {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  run post_tool s1 Glob '{"pattern":"*.go","path":"projects/api"}' "$BATS_TEST_TMPDIR"
  [[ "$(context)" == *"repos/acme/api/retry.md"* ]]
}

@test "an MCP call in scope activates the team with general/ only" {
  setup_team
  tm scope add acme mcp:acme-mcp
  run post_tool s1 mcp__acme-mcp__search_code '{"query":"x"}'
  [[ "$(context)" == *"general/es-error.md"* ]]
  [[ "$(context)" != *"- repos/"* ]]
  run post_tool s1 mcp__other__search '{"query":"x"}'
  [ -z "$output" ]
}

@test "a personal repo never activates a team, but is recorded as touched" {
  setup_team
  repo_at hobby git@github.com:someone/hobby.git
  run post_tool s1 Edit "{\"file_path\":\"$BATS_TEST_TMPDIR/hobby/main.go\"}"
  [ -z "$output" ]
  [ "$(jq -r '.touched | join(",")' "$TEAM_MEMORY_STATE/sessions/s1.json")" = "github.com/someone/hobby" ]
  [ "$(jq -r '.teams // {} | length' "$TEAM_MEMORY_STATE/sessions/s1.json")" = "0" ]
}

@test "reading the team clone itself does not count as touching a repo" {
  setup_team
  run post_tool s1 Read "{\"file_path\":\"$TEAM_MEMORY_HOME/acme/general/es-error.md\"}"
  [ -z "$output" ]
  [ "$(jq -r '.touched // [] | length' "$TEAM_MEMORY_STATE/sessions/s1.json" 2>/dev/null || echo 0)" = "0" ]
}

@test "a workspace folder of scope repos activates general/ at start" {
  setup_team
  repo_at ws/api git@github.com:acme/api.git
  repo_at ws/web git@github.com:acme/web.git
  mkdir -p "$BATS_TEST_TMPDIR/ws/notes"
  run session_start s1 "$BATS_TEST_TMPDIR/ws"
  [[ "$output" == *"general/es-error.md"* ]]
  [[ "$output" != *"- repos/"* ]]
  [ "$(jq -r '.teams.acme.signal' "$TEAM_MEMORY_STATE/sessions/s1.json")" = "workspace" ]
}

@test "a folder mixing scope and foreign repos is not a workspace" {
  setup_team
  repo_at ws/api git@github.com:acme/api.git
  repo_at ws/hobby git@github.com:someone/hobby.git
  run session_start s1 "$BATS_TEST_TMPDIR/ws"
  [ -z "$output" ]
  run post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/ws/api/x.go\"}"
  [[ "$(context)" == *"repos/acme/api/retry.md"* ]]
}

@test "workspace detection can be turned off per team" {
  setup_team
  tm set acme.workspace_detection false
  repo_at ws/api git@github.com:acme/api.git
  run session_start s1 "$BATS_TEST_TMPDIR/ws"
  [ -z "$output" ]
}

@test "a resumed session gets back the teams it activated earlier" {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  session_start s1 "$HOME"
  post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/x.go\"}"
  run hook SessionStart "{\"session_id\":\"s1\",\"cwd\":\"$HOME\",\"source\":\"compact\"}"
  [[ "$output" == *"repos/acme/api/retry.md"* ]]
}

@test "a team activated before its clone exists gets its index at the next prompt" {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_team
  repo_at projects/api git@github.com:acme/api.git
  run post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/projects/api/x.go\"}"
  [[ "$(context)" == *"being cloned"* ]]
  for _ in $(seq 50); do
    [ -d "$TEAM_MEMORY_HOME/acme/.git" ] && [ ! -d "$TEAM_MEMORY_STATE/teams/acme/lock" ] && break
    sleep 0.1
  done
  run prompt s1
  [[ "$output" == *"# Team memory: acme"* ]]
  [[ "$output" == *"general/es-error.md"* ]]
}

@test "parallel tool hooks do not lose each other's updates" {
  setup_team
  for i in 1 2 3 4 5 6; do
    repo_at "many/r$i" "git@github.com:someone/r$i.git"
    post_tool s1 Read "{\"file_path\":\"$BATS_TEST_TMPDIR/many/r$i/x\"}" >/dev/null &
  done
  wait
  [ "$(jq -r '.touched | length' "$TEAM_MEMORY_STATE/sessions/s1.json")" = "6" ]
}

@test "status lists recent sessions with their signals" {
  setup_team
  repo_at projects/api git@github.com:acme/api.git
  session_start s1 "$BATS_TEST_TMPDIR/projects/api" >/dev/null
  run tm status
  [[ "$output" == *"Recent sessions:"* ]]
  [[ "$output" == *"acme: active by repo github.com/acme/api, repos github.com/acme/api"* ]]
}
