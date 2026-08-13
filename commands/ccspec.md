---
description: Create a spec file for the current conversation and its tasks
argument-hint: [title or output path]
---
Create a SPEC markdown file capturing THIS conversation and the work involved. Write it with the Write tool; keep chat output to one line (the path).

1. Title: use `$ARGUMENTS` as the title if given, else derive a short title from the conversation.
2. Output path: if `$ARGUMENTS` ends in `.md`, use it as the path; otherwise write `<slug-of-title>.spec.md` in the current working directory.
3. Synthesize from the current conversation (you already have the full context). Use these sections:
   # <Title>
   ## Goal / Context
   ## Key Decisions
   ## Tasks  — `- [ ]` / `- [x]` checkbox items covering the work involved (done vs pending)
   ## Open Questions
   ## References (files, CRs, tickets, links)
4. Confirm the written path in one line.
