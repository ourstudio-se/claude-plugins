---
name: team-memory-move-to-team
description: Move the user's existing personal Claude memories about the team's repos, and team facts written as rules in their personal CLAUDE.md files, into team memory in one reviewed batch. The personal copy is removed after a backup, so team-memory restore-personal can put it back. Use when the user asks to move, share, promote or import their memories to the team, or to move one specific memory.
---

# Move personal memories to team memory

Moves verified team facts out of the user's personal memory into team memory, so each fact lives in one place. This is the one place where you ask before saving: it touches many memories at once, and personal memories were written without the team in mind.

Direction: personal → team. The personal copy is removed only after the team memory is pushed and the personal file is backed up. The way back is `team-memory restore-personal` (the exact originals) or the team-memory-copy-to-personal skill (the current team versions), both meant for leaving team memory.

Start with `team-memory status`. Team memory must be active in this session for the team you move into, and memories under `repos/<owner>/<repo>/` can only go to repos this session has worked in. If a repo you need is not touched yet, read a file in it first.

## 1. Scan, only within the team's scope

Only memories from the team's own work are candidates. Personal projects, other clients and anything else outside the team's scope are never read, let alone moved.

```
team-memory personal-folders <team>
```

It lists every personal memory folder with the folder its sessions started in, marked `in` (a repo of the team's scope, or a workspace folder of them), `out` or `unknown`.

- **`in` folders:** read their memories (`*.md`, skip `MEMORY.md`). Even here a memory can be about other work, from a session that touched several repos: it is a candidate only when it is about the team's repos or platform.
- **`out` folders:** never open them.
- **`unknown` folders:** do not open them; list them in the report so the user can say if one belongs to the team.
- **`~/.claude/CLAUDE.md`,** the user's own instructions for all projects: only rules that are verified facts about the team's repos or platform are candidates. Instructions about how the user wants Claude to work, and anything about other work, stay.
- **`CLAUDE.local.md`** (the user's uncommitted, personal file) in the team's repos: the same.
- **Never a `CLAUDE.md` committed in a repo:** it is already shared with everyone in that repo, and removing a rule from it would change the repo for everyone. When one holds a team fact, you may mention it in the report, but leave it.
- The existing team index, to find duplicates.

For a single memory ("move the ES error field memory to the team"), skip the scan and the table, and run steps 2 to 6 for that one.

## 2. Classify each item

- **Team:** a verified platform or repo fact, following the team memory rules in your context.
- **Personal:** feedback or preferences about how the user works, their own tasks, anything about one person.
- **Mixed:** a team fact plus personal notes, e.g. a root cause plus "I own the follow-up".
- **Stale:** dated or possibly no longer true. Check it against the code on the main branch, data or logs before proposing it; drop it if you cannot verify it.

## 3. Place, deduplicate and clean

- Folder: `general/` or `repos/<owner>/<repo>/`, by what the fact is about.
- Merge overlaps with existing team memories and with each other; prefer updating an existing team memory.
- Rewrite for a colleague without the original context: remove secrets, customer data, local paths, links to personal files and first-person notes; add a source link colleagues can open where there is one; set `date` to today only for facts you verified now, otherwise keep the original date.

## 4. Review with the user

Show one table: personal file, verdict, target file, new description, and what was cleaned. Show the rewritten text of any memory that changed a lot. The user ticks what goes, edits wording or overrides the folder. Save nothing before the user approves.

## 5. Save

Write each approved memory with Write. The hooks check the repo rule, the leak check and the secret scan on every write; when a write is refused, fix the memory or leave it personal and tell the user.

## 6. Remove the personal copy, only after the push

For each saved memory, run:

```
team-memory moved-to-team <personal file or CLAUDE.md> <team memory file>
```

It checks that the team memory has reached the remote, backs up the personal file to `~/.claude/team-memory-backup/` and records the move in a manifest, so `team-memory restore-personal` can put it back. Only when it succeeds:

- **Team:** delete the personal file and remove its line from that folder's `MEMORY.md`.
- **Mixed:** shrink the personal file to the personal part plus a link to the team memory, and update its `MEMORY.md` line.
- **Rule from `~/.claude/CLAUDE.md` or a `CLAUDE.local.md`:** remove the rule from that file, telling the user which line went.

If it says the memory is not pushed yet, wait a few seconds and run it again; never delete a personal file before it succeeds.

## 7. Report

One short summary: how many moved, merged, stayed personal or were dropped as stale, which folders were skipped as `unknown`, and that `team-memory restore-personal` puts the originals back if the user ever leaves team memory.
