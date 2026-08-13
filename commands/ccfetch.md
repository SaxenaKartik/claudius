---
description: Summarise another mapped conversation's context into this chat
argument-hint: <name-or-fragment of a mapped conversation>
---
Fetch and summarise the context of another Claude Code conversation from the resume map, so I can continue related work in THIS chat. Read-only — never resume or modify that session.

Note: this is a slash command, not a shell; there is no live keypress filter. Match `$ARGUMENTS` against the map by substring (see step 2) — that IS the filter.

1. **Map:** `{MAPPORT}`. Read it and extract every table row (skip header/separator/prose). Column 1 = name, column 2 = backtick-wrapped session id, column 3 = notes.
2. **Resolve name (case-insensitive):**
   - If `$ARGUMENTS` is empty → print a **numbered** list of all names (`1) <name>`, `2) <name>`, …) and ask "Reply 1–N (or a name)." Stop and wait.
   - Try **exact** match (case-insensitive). If exactly one → use it.
   - Else try **substring** match. If exactly one → use it.
   - If zero matches → say "No match for `<arg>`. Known:" and list the names. Stop.
   - If more than one → print a **numbered** list and ask me to reply with a number:
     ```
     "<arg>" matches N entries:
       1) <name>  (<short-id>)
       2) <name>  (<short-id>)
     Reply 1–N (or a name).
     ```
     **Stop and wait.** When I reply with a number, select that entry; if I reply with a name/fragment, re-run matching.
3. **Confirm before doing any work.** Once resolved to a single conversation, print
   `Found "<name>" (<short-id>). Fetch & summarise it? (y/n)` and **STOP — wait for my reply.**
   Do not read the transcript, spawn a subagent, or do anything else until I confirm.
   Only proceed if I answer yes/y; if I say no, stop.
4. **On confirmation** — locate the transcript `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/<id>.jsonl` (any workspace), read it, and produce a concise handoff summary: goal, key decisions/answers, current state, open next steps, key file / CR / ticket references. Short bullet points.
5. End by asking if I want to continue that work here.
