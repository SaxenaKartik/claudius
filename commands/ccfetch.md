---
description: Summarise another mapped conversation's context into this chat
argument-hint: <name of a mapped conversation>
---
Fetch and summarise the context of another Claude Code conversation from the resume map, so I can continue related work in THIS chat. Read-only — never resume or modify that session.

1. Map = `echo "${CC_MAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cc_map.md}"`. Find the table row whose name matches `$ARGUMENTS` (exact → case-insensitive → substring). If none match, say so and list the names. If more than one matches, list the candidates and ask which.
2. Take its session id from column 2, and locate the transcript: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/<id>.jsonl` (search all workspaces).
3. Read that transcript (JSONL; each line is a message/event) and produce a concise handoff summary: goal, key decisions/answers, current state, open next steps, and important file / CR / ticket references. Use short bullet points.
4. End by asking if I want to continue that work here.
