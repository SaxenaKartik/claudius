---
description: Export the current conversation's context to a markdown file
argument-hint: [output path]
---
Write a CONTEXT EXPORT markdown file capturing THIS conversation for handoff. Use the Write tool; keep chat output to one line (the path).

1. Output path: if `$ARGUMENTS` ends in `.md`, use it; otherwise write `<slug-of-title>.context.md` in the current working directory.
2. Synthesize from the current conversation. Sections: `# <Title>`, `## Overview`, `## What happened` (chronological key points), `## Decisions`, `## Current state`, `## References`.
3. Confirm the written path in one line.
