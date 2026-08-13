---
description: Show the current conversation's name in the resume map
---
Report the name THIS conversation is mapped to. One line of output.

1. Get the current session id: `echo "$CLAUDE_CODE_SESSION_ID"`.
2. In the map (`${CC_MAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cc_map.md}`), find the table row whose Session ID column equals that id.
3. If found, reply exactly: `This chat is mapped as "<name>".` Otherwise: `This chat is not in the map (add it with /ccadd).`
