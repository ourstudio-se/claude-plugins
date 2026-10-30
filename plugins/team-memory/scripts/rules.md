## Saving to team memory ({{team}})

Team memory is shared with everyone in {{team}}. Save to it only what is useful to all of them; everything else goes to personal memory as before. A fact lives in one place only: never in both team and personal memory.

Save a team memory when all of these hold:
- **Verified:** confirmed in code, data or logs during this session; not a guess or a theory from the middle of debugging.
- **True on the main branch:** it holds in the code as it is on main, not only on a feature branch, in a test environment or in uncommitted work. Working on a branch, save the lasting lesson now (root cause, gotcha, how services really interact), which is usually already true on main, and mention the change it led to: "Consumers retry three times because `maxRetries` is read from the wrong config key (fixed in <PR link>)".
- **About the platform:** a root cause, gotcha, contract between services or convention. How one person likes to work, and their ongoing tasks, stay personal.
- **Clean:** no secrets, tokens, customer data, registration numbers or names of people taken from data, and no local paths.
- **New:** check the index first, and update the existing memory instead of adding a near-duplicate.

When in doubt, save it to personal memory instead.

A detail that only exists on an unmerged branch (a new flag, endpoint or contract) goes to personal memory, with this line at the end so it is picked up once it is on main:
`Team memory after merge: <owner>/<repo>`
When a session later starts on the repo's default branch, you are reminded of these memories; check each against the code, move the ones that are now true into team memory, and leave the rest personal.

Where:
- `{{clone}}/repos/<owner>/<repo>/<slug>.md` for a fact about one repo. Only repos this session has worked in are allowed.
- `{{clone}}/general/<slug>.md` for a fact that spans repos or the whole platform.
- The slug uses a-z, 0-9 and - and names the fact, e.g. `es-error-field-mapping`.

Format:
```
---
name: <slug>
description: <one line that lets a colleague decide whether to open it>
metadata:
  type: project | reference | convention
  author: <the user's git email>
  date: <YYYY-MM-DD, the day the fact was last verified>
---

<The fact, written for a colleague who lacks this session's context.>

**Why:** <what breaks or why it matters>
**How to apply:** <what to do about it>

Source: <a link colleagues can open, such as the PR, issue or commit>
```
`project`: how or why a part of the platform works. `reference`: where to find something. `convention`: an agreed way of doing things.

Good: "Elasticsearch rejects `"error"` string attributes because the field is mapped as an object; log errors with the structured error helper", with the PR as source. Not for team memory: "the user prefers terse tests" (personal), "the retry bug is probably in the consumer" (not verified), "the new flag works on the test branch" (not on main).

After saving, tell the user in one line, as the hook's reply says: `Saved to team memory (<folder>): <description> · say "undo" to revert`. When the user says undo, run `team-memory undo`.

Using team memory: a memory reflects what was true when it was written. Before you act on one that names a file, function, flag or endpoint, check that it still holds in the code.

Keeping team memory right:
- When you prove a team memory wrong (verified, true on main), fix it, or delete it with `team-memory delete <file>`, and announce that the same way, with undo.
- When you use a memory marked stale and can verify it, update its `date`; when it is no longer true, fix or delete it. Never delete a memory only for being old.
- Change memory files only with Write and Edit; Bash may read them but not change them.
- Personal memory wins when the two disagree. A personal memory may link to a team memory to add the user's own angle without repeating the fact.
