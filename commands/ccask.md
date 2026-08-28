---
description: Answer a question using your OTHER saved chats (cross-chat, cited) — into this chat
argument-hint: <question about your past conversations>
---
Answer my question by drawing on my OTHER saved Claude Code conversations, and pull that context into THIS chat so I can keep working with it. Cite which chats each part comes from.

1. If `$ARGUMENTS` is empty, ask me what I want to know, then stop.
2. Retrieve the most relevant material from across all my chats by running this in the Bash tool. It ranks every session by relevance and prints focused excerpts (each block headed `### From chat: <name>`), WITHOUT making a nested model call — so it's fast and cheap:
   ```
   command -v ccask >/dev/null 2>&1 || source ~/.claude/cc_resume.zsh 2>/dev/null || source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudius.zsh" 2>/dev/null
   ccask -a --context "$ARGUMENTS"
   ```
   (To focus on specific chats instead of all of them, drop `-a` and add their names: `ccask --context "$ARGUMENTS" "Backend Changes" "Frontend Changes"`.)
3. If it prints a line starting `CANNOT ANSWER:` or nothing useful, tell me the answer isn't in my saved chats and stop — do NOT guess or use outside knowledge.
4. Otherwise answer `$ARGUMENTS` **strictly from those excerpts**: quote exact formulas, numbers, code line references, and file/CR/ticket identifiers when present, and CITE the chat name(s) each part comes from, e.g. (from "Backend Changes"). Never invent anything not in the excerpts.
5. Briefly note that this context is now in the chat if I want to keep going.
