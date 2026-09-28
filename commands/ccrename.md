---
description: Rename the current conversation in the resume map (one-cell edit)
argument-hint: <new name>
---
Mechanical one-cell edit — NOT a task. Do not analyze or plan; keep total output to one line.

1. id = output of `echo "$CLAUDE_CODE_SESSION_ID"`.
2. Map = `{MAPPORT}`.
3. If `$ARGUMENTS` is empty, reply `usage: /ccrename <new name>` and stop.
4. If `id` is not in the map, reply `this chat isn't mapped yet — use /ccadd <name>` and stop.
5. If a DIFFERENT row already has the name `$ARGUMENTS` (case-insensitive), reply `"<name>" is already used by another chat` and stop.
6. Else edit ONLY the name cell of the row containing `id` (the text between the first and second `|`) to `$ARGUMENTS` (Edit tool; keep the id, summary and every other line unchanged).
7. Reply with exactly: `Renamed "<old>" -> "<new>"`.
