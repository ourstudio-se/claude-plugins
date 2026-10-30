# team-memory

Shared Claude Code memory for a team. Memories are markdown files in a git repo the team owns: general memories in `general/`, repo-specific ones in `repos/<owner>/<repo>/`. The plugin loads the relevant ones into every session that works in the team's repos, and lets Claude save new ones the same way it saves personal memory.

## Install

```sh
claude plugin install team-memory --marketplace ourstudio-se/claude-plugins
team-memory teams add <team> <memory repo url>
team-memory scope add <team> github.com/<org> [mcp:<server>...]
```

`team-memory` is on the PATH of Claude Code's Bash tool; outside Claude Code it is in the plugin's install folder under `bin/`. A team's own setup tool usually runs these steps.

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

## Settings

All settings live in one local file, `~/.config/claude-team-memory/teams.json` by default; the plugin option `settings_path` changes the path. Nothing in a memory repo can change them.

## License

[MIT](../../LICENSE)
