---
name: team-memory-import
description: Move existing personal Claude memories, and team facts written as rules in CLAUDE.md files, into team memory in one reviewed batch, with a backup so they can be restored. Use when the user asks to import, share, move or promote their memories to the team, or to promote one specific memory.
---

# Import personal memories into team memory

Moves verified team facts out of the user's personal memory into team memory, so each fact lives in one place. This is the one place where you ask before saving: it touches many memories at once, and personal memories were written without the team in mind.

Start with `team-memory status`. Team memory must be active in this session for the team you import into, and memories under `repos/<owner>/<repo>/` can only go to repos this session has worked in. If a repo you need is not touched yet, read a file in it first.

## 1. Scan

- Every personal memory folder: `~/.claude/projects/*/memory/*.md` (skip `MEMORY.md`).
- The user's CLAUDE.md files: `~/.claude/CLAUDE.md` and those in the project folders. Only rules that are really team facts are candidates; instructions about how the user wants Claude to work stay.
- The existing team index, to find duplicates.

For a single memory ("promote the ES error field memory"), skip the scan and the table, and run steps 2 to 6 for that one.

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
team-memory imported <personal file> <team memory file>
```

It checks that the team memory has reached the remote, backs up the personal file to `~/.claude/team-memory-backup/` and records the move in a manifest, so `team-memory-export` can restore it. Only when it succeeds:

- **Team:** delete the personal file and remove its line from that folder's `MEMORY.md`.
- **Mixed:** shrink the personal file to the personal part plus a link to the team memory, and update its `MEMORY.md` line.
- **CLAUDE.md rule:** remove the rule from the CLAUDE.md file, telling the user which line went.

If it says the memory is not pushed yet, wait a few seconds and run it again; never delete a personal file before it succeeds.

## 7. Report

One short summary: how many moved, merged, stayed personal or were dropped as stale, and that `team-memory-export` brings them back if needed.
