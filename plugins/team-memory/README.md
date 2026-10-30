# team-memory

Shared Claude Code memory for a team. Memories are markdown files in a git repo the team owns: general memories in `general/`, repo-specific ones in `repos/<owner>/<repo>/`. The plugin loads the relevant ones into every session that works in the team's repos, and lets Claude save new ones the same way it saves personal memory.

## Install

```sh
claude plugin install team-memory --marketplace ourstudio-se/claude-plugins
team-memory teams add <team> <memory repo url>
team-memory scope add <team> github.com/<org> [mcp:<server>...]
```

`team-memory` is on the PATH of Claude Code's Bash tool; outside Claude Code it is in the plugin's install folder under `bin/`. A team's own setup tool usually runs these steps.

**Restart running sessions** after installing or updating: `/exit`, then `claude --continue` in the same folder. Team memory is loaded when a session starts; `/reload-plugins` loads the plugin but does not inject team memory.

To get new versions automatically, turn on auto-update for the marketplace (`/plugin` → Marketplaces → ourstudio → Enable auto-update); new versions then install when Claude Code starts.

## Requirements

- Linux, macOS, or Windows via WSL (native Windows is not supported)
- `git`, `gh`, `jq`, `curl`, and `sha256sum` (or `shasum` on macOS)

The plugin checks these at session start and tells Claude what is missing.

## How it works

- **Reading:** at session start, and when a session first works in one of the team's repos, Claude gets an index: one line per memory for `general/` (up to 900) and for that repo's folder (up to 600). Claude reads a memory when its line looks relevant. Memories colleagues push arrive at the next prompt.
- **Writing:** Claude saves verified platform facts on its own and says so in one line; "undo" reverts. Before a save, hooks check the folder, refuse text from work outside the team, and scan for secrets; after it, they commit and push in the background.
- **Scope:** a team turns on only when the session works in its repos (by git origin owner), calls one of its MCP servers, or starts in a folder of its repos.

## Moving memories between personal and team memory

| | Direction | What happens to the original |
|---|---|---|
| `/team-memory-move-to-team` (skill) | personal → team | Removed from personal memory after the team memory is pushed, with a backup in `~/.claude/team-memory-backup/` |
| `team-memory restore-personal` | team → personal | Puts back exactly what was moved, from the backups. Team memory is not touched |
| `/team-memory-copy-to-personal` (skill) | team → personal | Copies the memories you created, as the current team version or the original. Team memory keeps them |

Moving to the team is the normal direction: a fact should live in one place. The way back is for leaving a team or turning team memory off; while the team is still on, both ask first, since the facts would then exist twice.

## Commands

`/team-memory` in Claude Code, or `team-memory` in a shell:

| Command | What it does |
|---|---|
| `status` | Settings, teams, clones and recent sessions |
| `teams add\|remove`, `scope add\|remove` | Which teams, their memory repos and what turns them on |
| `set <key> <value>` | e.g. `pull_interval_minutes`, `max_general_index_lines`, `<team>.enabled` |
| `private add\|remove <host>/<owner>` | Owners whose repo names must never appear in team memory |
| `pause`, `resume` | Turn team memory off or on for the current session |
| `undo`, `delete <file>` | Revert the last save, or delete a memory, in the current session |
| `restore-personal` | See above |

## Configuration

There are two places, on purpose: what decides **where** team memory turns on is local to each user, and what a team writes **into** its memory is in the memory repo.

### Your settings (local)

One file, `~/.config/claude-team-memory/teams.json` (the plugin option `settings_path` moves it). Change it with the commands above rather than by hand; `team-memory status` shows it. Nothing in a memory repo can change it, so nobody can widen your scope by pushing.

```json
{
  "pull_interval_minutes": 5,
  "stale_after_months": 6,
  "max_general_index_lines": 900,
  "max_repo_index_lines": 600,
  "private_owners": ["github.com/other-client"],
  "teams": {
    "acme": {
      "repo": "git@github.com:acme/claude-team-memory.git",
      "scope": ["github.com/acme", "mcp:acme-mcp"],
      "workspace_detection": true,
      "enabled": true
    }
  }
}
```

| Setting | Default | What it does |
|---|---|---|
| `pull_interval_minutes` | 5 | How often a session pulls colleagues' memories (at a prompt) |
| `stale_after_months` | 6 | Older memories are marked stale in the index |
| `max_general_index_lines` | 900 | Lines listed for `general/`; the rest stay searchable in the clone |
| `max_repo_index_lines` | 600 | Lines listed per repo folder |
| `private_owners` | none | Owners whose repo names must never appear in team memory; your own GitHub account always counts |
| `teams.<name>.repo` | | The team's memory repo |
| `teams.<name>.scope` | | What turns the team on: `<host>/<owner>` for repos (by git origin), `mcp:<server>` for MCP servers |
| `teams.<name>.workspace_detection` | true | Turn on from the start in a folder whose subfolders are the team's repos |
| `teams.<name>.enabled` | true | Turn the team off without removing it |

Examples: `team-memory set pull_interval_minutes 10`, `team-memory set acme.enabled false`, `team-memory scope add acme mcp:acme-test-mcp`, `team-memory private add github.com/other-client`.

### The team's settings (memory repo)

`team-memory.json` at the root of the memory repo is shown to Claude with the index:

```json
{
  "team": "acme",
  "guidelines": [
    "Write memories in English.",
    "Link the PR or ticket that confirms a fact as its source."
  ],
  "secret_patterns": [
    {"name": "acme-api-key", "regex": "ACME-[0-9]{8}"}
  ]
}
```

- `guidelines`: team rules Claude follows on top of the plugin's own writing rules.
- `secret_patterns`: extra patterns (extended regex) checked with the built-in ones and gitleaks before every save. They can add checks, never turn built-in ones off.

Memories themselves live in `general/` (the whole platform) and `repos/<owner>/<repo>/` (one repo), one markdown file per memory.

## License

[MIT](../../LICENSE)
