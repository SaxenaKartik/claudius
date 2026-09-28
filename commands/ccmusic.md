---
description: Play / pause / resume / stop background music (shown in the status line)
argument-hint: [play] [-s] <file|folder|URL> | pause | resume | toggle | next | prev | stop | status
---
Mechanical — NOT a task. Run this in the Bash tool, then reply with ONLY its one-line output.
Put any URL or file path from `$ARGUMENTS` in SINGLE QUOTES (URLs often contain `&`, `?`, `=`), keep the other words bare:
```
command -v ccmusic >/dev/null 2>&1 || source ~/.claude/cc_resume.zsh 2>/dev/null || source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudius.zsh" 2>/dev/null
ccmusic <$ARGUMENTS, with the URL/path single-quoted>
```
A bare URL or path means `play`.
