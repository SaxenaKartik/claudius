---
description: Explain a mapped conversation in plain terms — Done / Pending / Next
argument-hint: <name of a mapped conversation>
---
Explain another Claude Code conversation in simple, plain terms for someone new to it. Read-only — do not resume or modify that session.

1. Map = `echo "${CC_MAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cc_map.md}"`. Find the row whose name matches `$ARGUMENTS` (exact → case-insensitive → substring). If none match, say so and list the names. If multiple match, list candidates and ask which.
2. Take its session id from column 2, and locate the transcript: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/<id>.jsonl`.
3. Read that transcript. Produce exactly three sections, jargon-light and concrete: `## Done`, `## Pending`, `## Next`. Keep it brief.
