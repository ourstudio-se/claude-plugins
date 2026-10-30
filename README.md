# claude-plugins

Claude Code plugins from ourstudio.

| Plugin | What it does |
|---|---|
| [team-memory](plugins/team-memory) | Shared Claude Code memory for a team, stored in a git repo |

## Install

```sh
claude plugin marketplace add ourstudio-se/claude-plugins
claude plugin install team-memory@ourstudio
```

## Contributing

Changes to `main` go through a reviewed pull request, since plugin code runs on every user's machine.

Run the tests with the vendored [bats-core](tests/bats/VERSION):

```sh
tests/bats/bin/bats tests/team-memory
```

## License

[MIT](LICENSE)
