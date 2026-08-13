---
description: Explain a mapped conversation in plain terms — Done / Pending / Next
argument-hint: <name-or-fragment of a mapped conversation>
---
Explain another Claude Code conversation in simple, plain terms for someone new to it. Read-only — do not resume or modify that session.

Note: this is a slash command, not a shell; there is no live keypress filter. Match `$ARGUMENTS` against the map by substring (see step 2) — that IS the filter.

1. **Map:** `{MAPPORT}`. Read it and extract every table row (skip header/separator/prose). Column 1 = name, column 2 = backtick-wrapped session id.
2. **Resolve name (case-insensitive):**
   - Empty `$ARGUMENTS` → print a **numbered** list of all names (`1) <name>`, …) and ask "Reply 1–N (or a name)." Stop and wait.
   - Try **exact** match. If one → use it. Else **substring**. If one → use it.
   - Zero → "No match for `<arg>`. Known:" list. Stop.
   - Multiple → print a **numbered** list and ask me to reply with a number:
     ```
     "<arg>" matches N:
       1) <name>  (<short-id>)
       2) <name>  (<short-id>)
     Reply 1–N (or a name).
     ```
     **Stop and wait.** A number selects that entry; a name/fragment re-runs matching.
3. **Confirm before doing any work.** Once resolved to a single conversation, print
   `Found "<name>" (<short-id>). Explain it? (y/n)` and **STOP — wait for my reply.**
   Do not read the transcript or spawn a subagent until I confirm. Proceed only on yes.
4. **On confirmation** — locate the transcript `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/<id>.jsonl` (any workspace), read it, and explain plainly, jargon-light, in exactly three sections:
   ## Done — what was accomplished
   ## Pending — what's unfinished or in progress
   ## Next — what should be done next
