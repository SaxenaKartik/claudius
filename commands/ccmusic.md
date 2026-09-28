---
description: Play / pause / resume / stop background music (shown in the status line)
argument-hint: play [-s] <file|folder|URL> | pause | resume | next | stop | status
---
Mechanical — NOT a task. Run exactly this in the Bash tool, then reply with ONLY its one-line output:
```
command -v ccmusic >/dev/null 2>&1 || source ~/.claude/cc_resume.zsh 2>/dev/null || source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudius.zsh" 2>/dev/null
ccmusic $ARGUMENTS
```
