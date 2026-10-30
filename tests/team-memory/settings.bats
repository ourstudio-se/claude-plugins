load helpers

@test "status without a settings file shows defaults and no teams" {
  run tm status
  [ "$status" -eq 0 ]
  [[ "$output" == *"pull_interval_minutes: 5"* ]]
  [[ "$output" == *"max_general_index_lines: 900"* ]]
  [[ "$output" == *"No teams yet"* ]]
}

@test "teams add creates the file with defaults for the team" {
  run tm teams add acme git@github.com:acme/claude-team-memory.git
  [ "$status" -eq 0 ]
  [ "$(setting '.teams.acme.repo')" = "git@github.com:acme/claude-team-memory.git" ]
  [ "$(setting '.teams.acme.enabled')" = "true" ]
  [ "$(setting '.teams.acme.workspace_detection')" = "true" ]
  [ "$(setting '.teams.acme.scope | length')" = "0" ]
}

@test "teams add again changes the repo and keeps the scope" {
  tm teams add acme git@github.com:old/repo.git
  tm scope add acme github.com/acme
  run tm teams add acme git@github.com:new/repo.git
  [ "$status" -eq 0 ]
  [ "$(setting '.teams.acme.repo')" = "git@github.com:new/repo.git" ]
  [ "$(setting '.teams.acme.scope[0]')" = "github.com/acme" ]
}

@test "teams add rejects invalid names" {
  for name in Acme "../x" "-x" ""; do
    run tm teams add "$name" git@github.com:x/y.git
    [ "$status" -eq 1 ]
  done
}

@test "scope add dedupes and scope remove removes" {
  tm teams add acme git@github.com:x/y.git
  tm scope add acme github.com/acme mcp:acme-mcp
  tm scope add acme github.com/acme mcp:acme-test-mcp
  [ "$(setting '.teams.acme.scope | length')" = "3" ]
  run tm scope remove acme mcp:acme-mcp
  [ "$status" -eq 0 ]
  [ "$(setting '.teams.acme.scope | join(",")')" = "github.com/acme,mcp:acme-test-mcp" ]
}

@test "scope add rejects invalid entries and unknown teams" {
  tm teams add acme git@github.com:x/y.git
  for entry in "acme" "github.com" "mcp:" "/home/someone/projects"; do
    run tm scope add acme "$entry"
    [ "$status" -eq 1 ]
  done
  run tm scope add other github.com/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"no team named 'other'"* ]]
}

@test "set changes global and team settings with validation" {
  tm teams add acme git@github.com:x/y.git
  tm set pull_interval_minutes 10
  tm set acme.enabled false
  [ "$(setting '.pull_interval_minutes')" = "10" ]
  [ "$(setting '.teams.acme.enabled')" = "false" ]
  run tm set pull_interval_minutes 0
  [ "$status" -eq 1 ]
  run tm set acme.enabled maybe
  [ "$status" -eq 1 ]
  run tm set unknown 1
  [ "$status" -eq 1 ]
}

@test "teams remove keeps the clone unless --purge" {
  tm teams add acme git@github.com:x/y.git
  mkdir -p "$TEAM_MEMORY_HOME/acme"
  tm teams remove acme
  [ -d "$TEAM_MEMORY_HOME/acme" ]
  [ "$(setting '.teams | has("acme")')" = "false" ]
  tm teams add acme git@github.com:x/y.git
  tm teams remove acme --purge
  [ ! -d "$TEAM_MEMORY_HOME/acme" ]
}

@test "status shows teams, scope and clone state" {
  tm teams add acme git@github.com:x/y.git
  tm scope add acme github.com/acme
  run tm status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Team acme (enabled)"* ]]
  [[ "$output" == *"scope: github.com/acme"* ]]
  [[ "$output" == *"not cloned yet"* ]]
}

@test "an invalid settings file is reported, not overwritten" {
  mkdir -p "$(dirname "$TEAM_MEMORY_SETTINGS")"
  echo "{broken" >"$TEAM_MEMORY_SETTINGS"
  run tm teams add acme git@github.com:x/y.git
  [ "$status" -eq 1 ]
  [ "$(cat "$TEAM_MEMORY_SETTINGS")" = "{broken" ]
}

@test "the settings path option is used when no override is set" {
  unset TEAM_MEMORY_SETTINGS
  export CLAUDE_PLUGIN_OPTION_SETTINGS_PATH="$BATS_TEST_TMPDIR/other.json"
  tm teams add acme git@github.com:x/y.git
  [ -f "$BATS_TEST_TMPDIR/other.json" ]
}

@test "private add and remove change private_owners" {
  tm private add github.com/other-client
  tm private add github.com/other-client
  [ "$(setting '.private_owners | join(",")')" = "github.com/other-client" ]
  run tm private add other-client
  [ "$status" -eq 1 ]
  tm private remove github.com/other-client
  [ "$(setting '.private_owners | length')" = "0" ]
}
