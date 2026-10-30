load helpers

@test "SessionStart is silent when all tools are installed" {
  run hook SessionStart '{"session_id":"s1","source":"startup"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pause applies to the next session hook and is consumed" {
  tm pause
  run hook PostToolUse '{"session_id":"s1","tool_name":"Bash"}'
  [ "$status" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == *"paused in this session"* ]]
  [ "$(jq -r .paused "$TEAM_MEMORY_STATE/sessions/s1.json")" = "true" ]
  [ ! -f "$TEAM_MEMORY_STATE/request" ]

  run hook UserPromptSubmit '{"session_id":"s2"}'
  [ -z "$output" ]
  [ ! -f "$TEAM_MEMORY_STATE/sessions/s2.json" ]
}

@test "resume clears the pause in UserPromptSubmit as plain text" {
  tm pause
  hook UserPromptSubmit '{"session_id":"s1"}'
  tm resume
  run hook UserPromptSubmit '{"session_id":"s1"}'
  [ "$output" = "team-memory: resumed in this session." ]
  [ "$(jq -r .paused "$TEAM_MEMORY_STATE/sessions/s1.json")" = "false" ]
}

@test "an old pause request is ignored" {
  mkdir -p "$TEAM_MEMORY_STATE"
  echo "pause $(($(date +%s) - 600))" >"$TEAM_MEMORY_STATE/request"
  run hook UserPromptSubmit '{"session_id":"s1"}'
  [ -z "$output" ]
  [ ! -f "$TEAM_MEMORY_STATE/sessions/s1.json" ]
}

@test "an unsafe session id is ignored" {
  tm pause
  run hook UserPromptSubmit '{"session_id":"../../etc"}'
  [ -z "$output" ]
  [ -f "$TEAM_MEMORY_STATE/request" ]
}
