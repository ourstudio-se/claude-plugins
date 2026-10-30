---
name: team-memory-copy-to-personal
description: Copy the team memories the user created into their personal Claude memory, as the current team version or as the original from before they were moved to the team. Team memory keeps them. Meant for leaving a team or turning team memory off. Use when the user wants their memories in personal memory, is leaving a team or removing team memory, or asks to copy, restore or export team memories to personal memory.
---

# Copy team memories to personal memory

Copies the memories the user created in team memory into their personal memory. Direction: team → personal. Team memory keeps them: colleagues may rely on those memories. Removing one from the team is a separate, explicit step (`team-memory delete <file>`, with undo), only when the user asks.

To put back exactly what was moved to the team, without changes from colleagues, `team-memory restore-personal` does it without this skill. Use this skill for memories written straight to team memory, for the current team versions, or to choose per memory.

## 0. Avoid duplicates

This is for leaving: while the team is still on, the copied facts would exist twice, in personal and team memory. The personal copies win in the user's sessions and stop getting colleagues' fixes. Run `team-memory status`:

- **The team is still enabled:** say so, and ask whether the user is leaving the team or turning team memory off. If yes, turn it off first with `team-memory set <team>.enabled false` (or `team-memory teams remove <team>`), then continue. If they want to keep team memory on, stop: the memories are already available to them through team memory.
- **The team is disabled or removed:** continue.

A single memory the user explicitly wants personal ("I want my own version of this") is fine with the team on; say that the team memory stays and that their personal copy now wins in their sessions.

## 1. Find the user's memories

```
team-memory mine --json
```

Each entry has the team, the memory file, its description, and for memories moved from personal memory where they came from: `personal` (the original file), `backup` (the copy saved at the move) and `index_line` (its old `MEMORY.md` line).

## 2. Choose the version, once for the whole run

Ask the user:
- **Current team version** (recommended): keeps what colleagues improved since.
- **Original from the backup:** exactly as it was before the move, for memories that have a backup. Others use the current team version.

## 3. Choose where each memory goes

- Memories moved from personal memory go back to the folder they came from (the folder of `personal`), under their original file name.
- Memories written straight to team memory go to the personal memory folder of the current project (`~/.claude/projects/<project>/memory/`), unless the user picks another.
- When a personal file with that name already exists, show both and let the user choose: keep, replace or merge.

## 4. Convert

Personal memory uses the same frontmatter, except:
- Remove `author`.
- Keep `type` only when it is a personal memory type (user, feedback, project, reference); turn `convention` into `project`.
- Keep the body and the source link.

## 5. Review with the user

Show one table: team memory, version, target personal file, and whether it replaces something. Write nothing before the user approves.

## 6. Write and index

Write each approved file into the personal memory folder, then add one line per memory to that folder's `MEMORY.md`: the `index_line` from the move when there is one, otherwise `- [<title>](<file>) — <description>`. Never duplicate a line that is already there.

## 7. Report

One short summary: how many were copied and where, and whether team memory is now off. The team memories themselves stay in the team repo for colleagues.
