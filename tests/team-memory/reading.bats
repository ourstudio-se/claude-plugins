load helpers

@test "repo keys from the common origin url forms" {
  . "$PLUGIN/scripts/lib/repo.sh"
  [ "$(tm_repo_url_key git@github.com:acme/process-flow.git)" = "github.com/acme/process-flow" ]
  [ "$(tm_repo_url_key https://github.com/acme/process-flow)" = "github.com/acme/process-flow" ]
  [ "$(tm_repo_url_key https://GitHub.com/acme/process-flow.git/)" = "github.com/acme/process-flow" ]
  [ "$(tm_repo_url_key ssh://git@github.com:22/acme/process-flow.git)" = "github.com/acme/process-flow" ]
  [ "$(tm_repo_url_key https://user@gitlab.com/group/sub/repo.git)" = "gitlab.com/group/sub/repo" ]
  run tm_repo_url_key /tmp/local/repo.git
  [ "$status" -eq 1 ]
}

@test "session start in a scope repo clones and injects general and repo lines" {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_memory repos/acme/api/retry.md "$(today)" "api retries twice"
  add_memory repos/acme/web/theme.md "$(today)" "web theme gotcha"
  add_team
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Team memory: acme"* ]]
  [[ "$output" == *"- general/es-error.md: ES rejects string error fields"* ]]
  [[ "$output" == *"- repos/acme/api/retry.md: api retries twice"* ]]
  [[ "$output" != *"theme"* ]]
  [ -d "$TEAM_MEMORY_HOME/acme/.git" ]
}

@test "session start outside the scope injects nothing" {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_team
  make_work_repo git@github.com:someone/hobby.git
  run session_start s1 "$WORK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a disabled team is not injected" {
  make_remote
  add_team
  tm set acme.enabled false
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [ -z "$output" ]
}

@test "frontmatter quotes are removed only when they wrap the whole value" {
  . "$PLUGIN/scripts/lib/index.sh"
  printf -- '---\ndescription: "error" string attrs are rejected\ndate: "2026-09-12"\n---\n' >"$BATS_TEST_TMPDIR/a.md"
  [ "$(tm_frontmatter "$BATS_TEST_TMPDIR/a.md")" = "2026-09-12	\"error\" string attrs are rejected" ]
  printf -- "---\ndescription: 'quoted'\n---\nbody\ndescription: not frontmatter\n" >"$BATS_TEST_TMPDIR/b.md"
  [ "$(tm_frontmatter "$BATS_TEST_TMPDIR/b.md")" = "	quoted" ]
}

@test "old and undated memories are marked" {
  make_remote
  add_memory general/old.md 2020-01-01 "old fact"
  add_memory general/undated.md "" "undated fact"
  add_team
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [[ "$output" == *"- general/old.md: old fact (stale, verified 2020-01-01)"* ]]
  [[ "$output" == *"- general/undated.md: undated fact (no date)"* ]]
}

@test "general/ is capped at max_general_index_lines, newest first" {
  make_remote
  add_memory general/a.md 2026-01-01 "oldest"
  add_memory general/b.md 2026-02-01 "middle"
  add_memory general/c.md 2026-03-01 "newest"
  add_team
  tm set max_general_index_lines 2
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [[ "$output" == *"newest"* ]]
  [[ "$output" == *"middle"* ]]
  [[ "$output" != *"oldest"* ]]
  [[ "$output" == *"1 older memories in general/ are not listed"* ]]
}

@test "a memory pushed later arrives at the next prompt, once" {
  make_remote
  add_memory general/first.md "$(today)" "first fact"
  add_team
  make_work_repo git@github.com:acme/api.git
  session_start s1 "$WORK"
  add_memory repos/acme/api/second.md "$(today)" "second fact"
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  run prompt s1
  [ "$output" = "Team memory (acme) changed since you last saw its index; new or updated lines:
- repos/acme/api/second.md: second fact" ]
  [[ "$output" != *"first fact"* ]]
  run prompt s1
  [ -z "$output" ]
}

@test "a prompt starts a pull when the last one is older than the interval" {
  make_remote
  add_team
  make_work_repo git@github.com:acme/api.git
  session_start s1 "$WORK"
  echo 0 >"$TEAM_MEMORY_STATE/teams/acme/last_pull"
  add_memory general/later.md "$(today)" "later fact"
  prompt s1
  for _ in $(seq 50); do
    [ "$(cat "$TEAM_MEMORY_STATE/teams/acme/last_pull")" != 0 ] && break
    sleep 0.1
  done
  run prompt s1
  [[ "$output" == *"- general/later.md: later fact"* ]]
}

@test "when the clone is not ready at start, the whole index arrives at the next prompt" {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_team
  make_work_repo git@github.com:acme/api.git
  # A held lock stands in for a clone that takes longer than the wait.
  mkdir -p "$TEAM_MEMORY_STATE/teams/acme/lock"
  run session_start s1 "$WORK"
  [[ "$output" == *"still being cloned"* ]]
  rmdir "$TEAM_MEMORY_STATE/teams/acme/lock"
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  run prompt s1
  [[ "$output" == *"- general/es-error.md: ES rejects string error fields"* ]]
}

@test "offline: the existing clone is used as it is" {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_team
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  mv "$REMOTE" "$REMOTE.gone"
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [[ "$output" == *"- general/es-error.md: ES rejects string error fields"* ]]
}

@test "a rewritten remote history replaces the clone and says so at the next start" {
  make_remote
  add_memory general/leak.md "$(today)" "contains a leak"
  add_team
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  git -C "$SEED" reset -q --hard HEAD~1
  git -C "$SEED" push -q --force origin main
  "$PLUGIN/scripts/sync.sh" acme "$REMOTE"
  [ ! -f "$TEAM_MEMORY_HOME/acme/general/leak.md" ]
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [[ "$output" == *"history was rewritten"* ]]
  [[ "$output" != *"leak.md"* ]]
}

@test "a paused session gets no index" {
  make_remote
  add_memory general/es-error.md "$(today)" "ES rejects string error fields"
  add_team
  make_work_repo git@github.com:acme/api.git
  tm pause
  prompt s1
  run session_start s1 "$WORK"
  [ -z "$output" ]
}

@test "a repo folder is capped at max_repo_index_lines, newest first" {
  make_remote
  add_memory repos/acme/api/a.md 2026-01-01 "oldest"
  add_memory repos/acme/api/b.md 2026-02-01 "middle"
  add_memory repos/acme/api/c.md 2026-03-01 "newest"
  add_team
  tm set max_repo_index_lines 2
  make_work_repo git@github.com:acme/api.git
  run session_start s1 "$WORK"
  [[ "$output" == *"newest"* ]]
  [[ "$output" == *"middle"* ]]
  [[ "$output" != *"oldest"* ]]
  [[ "$output" == *"1 older memories in repos/acme/api/ are not listed; search $TEAM_MEMORY_HOME/acme/repos/acme/api when needed."* ]]
}

@test "the default limits are 900 for general/ and 600 per repo" {
  run tm status
  [[ "$output" == *"max_general_index_lines: 900"* ]]
  [[ "$output" == *"max_repo_index_lines: 600"* ]]
}
