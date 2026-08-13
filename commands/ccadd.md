---
description: Add the current conversation to the resume map (one-row append)
argument-hint: [conversation name]
---
Mechanical one-row edit — NOT a task. Do not analyze, do not write a multi-section plan; if plan mode is on, the plan is literally "append one row". Keep total output to one line.

1. id = output of `echo "$CLAUDE_CODE_SESSION_ID"`.
2. Map = `echo "${CC_MAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cc_map.md}"`.
3. If `id` is already in the map, reply "already mapped as <name>" and stop.
4. Else append ONE row right after the last table row (Edit tool, preserve all other lines):
   `| $ARGUMENTS | ` + backtick + id + backtick + ` | <=12-word summary> |`
5. Reply with exactly: `Added "<name>" -> <id>`.
