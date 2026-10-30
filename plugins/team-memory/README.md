# team-memory

Shared Claude Code memory for a team. Memories are markdown files in a git repo the team owns: general memories in `general/`, repo-specific ones in `repos/<owner>/<repo>/`. The plugin loads the relevant ones into every session and lets Claude save new ones the same way it saves personal memory.

> Work in progress: version 0.1.0 only installs the hooks and checks requirements.

## Install

```sh
claude plugin install team-memory --marketplace ourstudio-se/claude-plugins
```

## Requirements

- Linux, macOS, or Windows via WSL (native Windows is not supported)
- `git`, `gh`, `jq`, `curl`, and `sha256sum` (or `shasum` on macOS)

The plugin checks these at session start and tells Claude what is missing.

## Settings

All settings live in one local file, `~/.config/claude-team-memory/teams.json` by default. The path can be changed with the plugin option `settings_path`.

## License

[MIT](../../LICENSE)
