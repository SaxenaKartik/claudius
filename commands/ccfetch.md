---
description: Summarise one or more mapped conversations' context into this chat
argument-hint: <name(s)-or-fragment(s) of mapped conversations>
---
Fetch and summarise the context of one or more OTHER Claude Code conversations from the resume map, so I can continue related work in THIS chat. Read-only — never resume or modify those sessions. Because this runs inside the current chat, the summaries you produce become part of THIS conversation (that IS how the context gets pulled in).

Note: this is a slash command, not a shell; there is no live keypress filter. Match `$ARGUMENTS` against the map by substring (see step 2) — that IS the filter. `$ARGUMENTS` may name **several** conversations (space- or comma-separated).

1. **Map:** `{MAPPORT}`. Read it and extract every table row (skip header/separator/prose). Column 1 = name, column 2 = backtick-wrapped session id, column 3 = notes.
2. **Resolve the request:**
   - If `$ARGUMENTS` is empty → print a **numbered** list of all names (`1) <name>`, …) and ask "Reply with one or more numbers/names (comma-separated), or `all`." Stop and wait.
   - Otherwise split `$ARGUMENTS` into individual requests (by comma, or by whole quoted names). For **each** request, match case-insensitively: exact first, else substring.
     - Zero matches for a request → say "No match for `<req>`." and list the names; drop that request.
     - More than one match for a request → print a numbered list for that request and ask me to disambiguate; stop and wait.
   - Collect the resolved set of distinct conversations (name + short-id).
3. **Cache check + per-chat choice.** For each resolved conversation, check whether a cached summary exists at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudius-cache/<id>.fetch.md`. Then print one consolidated prompt, e.g.:
   ```
   Resolved 3 conversations:
     • MEM3            — cached (2h ago)   → [u]se / [r]egenerate?
     • LUK7 RCC        — cached (1d ago)   → [u]se / [r]egenerate?
     • Backend Changes — not cached        → will generate
   Reply with your choices (e.g. "use all", "regenerate LUK7", "u,u,r"), or just say "go" to use cached where available.
   ```
   **Stop and wait for my reply.** Default when I say "go"/nothing specific: reuse any cached summary, generate the uncached ones.
4. **Generate (in parallel via subagents).** For every conversation that needs (re)generation — i.e. uncached, or ones I chose to regenerate — locate its transcript `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/<id>.jsonl` (any workspace) and spawn **one subagent per conversation, all in a single message so they run in parallel**. Each subagent reads its transcript and returns a concise handoff summary: goal, key decisions/answers, current state, open next steps, key file / CR / ticket references — short bullet points. Conversations I chose to reuse: just read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudius-cache/<id>.fetch.md` directly (no subagent).
5. **Cache the fresh summaries.** Write each newly generated summary to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudius-cache/<id>.fetch.md` (overwrite) so future fetches are instant.
6. **Present the combined context** here, one `## <name>` section per conversation, in the order requested. This is the context now available in THIS chat.
7. End by asking what I want to do next with this context here.
