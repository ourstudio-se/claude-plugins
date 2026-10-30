---
name: team-memory-export
description: Copy the team memories the user created back into their personal Claude memory, either as the current team version or as the original from before an import. Use when the user wants their memories back, is leaving a team or removing team memory, or asks to restore, export or copy team memories to personal memory.
---

# Export team memories to personal memory

Copies the memories the user created in team memory into their personal memory. It never deletes anything from team memory: colleagues may rely on those memories. Removing them from the team is a separate, explicit step (`team-memory delete <file>`, with undo), only when the user asks.

## 1. Find the user's memories

```
team-memory mine --json
```

Each entry has the team, the memory file, its description, and for imported memories where it came from: `personal` (the original file), `backup` (the copy saved at import) and `index_line` (its old `MEMORY.md` line).

## 2. Choose the version, once for the whole run

Ask the user:
- **Current team version** (recommended): keeps what colleagues improved since.
- **Original from the backup:** exactly as it was before the import, for imported memories that have a backup. Others use the current team version.

## 3. Choose where each memory goes

- Imported memories go back to the personal folder they came from (the folder of `personal`), under their original file name.
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

Write each approved file into the personal memory folder, then add one line per memory to that folder's `MEMORY.md`: the `index_line` from the import when there is one, otherwise `- [<title>](<file>) — <description>`. Never duplicate a line that is already there.

## 7. Report

One short summary: how many were copied and where. Remind the user that the team memories are still in the team repo, and that a fact should live in one place: if they keep both, the personal copy wins in their own sessions.
