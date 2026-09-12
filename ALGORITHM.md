# ccask retrieval algorithm

How `ccask -a "<question>"` answers across your whole Claude Code history. Everything is local
except **one** model call (two if synonym expansion is on). Do the expensive part — understanding
your whole history — locally and cheaply with keyword search, then spend one model call on a small,
curated, cited answer.

```
question → tokenize → expand-synonyms★ → grep-rank chats → pick best turns → cited answer★
            [local]     [1 small call]       [local]           [local]        [1 model call]
```

## The pipeline

**1 · Tokenize — local.** Lowercase the question, drop stopwords, keep meaningful terms (≥3 chars).
`"how did we fix the DLQ redrive?"` → `fix, dlq, redrive`.

**2 · Expand for meaning — ADAPTIVE model call.** Claude suggests the words a transcript likely used,
so wording needn't match: `dead-letter queue` → `dlq, redrive, sqs, reprocess, poison, retry`. Semantic
recall **without embeddings or a vector DB**. **Adaptive:** this is a whole extra 12–45 s call, and it
only helps on a vocabulary gap — so it's skipped when the query already has a **discriminating** term
that appears (0 < df ≤ N/2, checked with one cheap local grep first). It fires only when *no* original
term discriminates (all absent, or all ubiquitous). `-e` forces it; `-E` / `CCASK_EXPAND=0` disables it.
Skipping the call is the main lever keeping a typical `ccask` to a single model call (~25–30 s).

**3 · Build the corpus — local.** List every `~/.claude/projects/*/*.jsonl`, dropping **ephemeral**
sessions (headless one-shots, seed sessions, slash-command runs) so the tool's own noise can't
pollute results. Ranking greps these **raw** transcripts directly; the compact extract isn't built
yet (that's step 5, only for chats that survive ranking).

**4 · Rank every chat — local `grep`, milliseconds, no model.** See scoring below. Sort, keep the
top `CCASK_TOPK` (default 5); chats matching nothing score 0 and are dropped.

**5 · Extract & select context — local (builds cache on first ask).** For each top chat, read its
**compact extract** (message text + the commands you actually ran + trimmed results, far smaller
than raw JSONL) — built once by a `python3` streaming pass (stdlib `json`, nothing to install) and
cached to `~/.claude/claudius-cache/<id>.text.md` (marker `claudius-extract v4`; a bump forces
rebuild); later asks reuse it. *(No `python3` → falls back to a capped slice of the raw transcript.)*
A long tool result is trimmed to **head + middle + tail**, not a blind head/tail cut: the dropped
middle is scanned and up to `MID_CAP` chars of its lines are spliced back as `[middle: …]`, so a fact
buried in the middle of a huge result survives. Which middle lines are kept depends on whether a
query is present:
- **`ccask` (query known):** the top-K extract is built **query-aware** — it keeps the middle lines
  matching your question terms + synonyms (a salient-content regex — errors, status/counts, IDs,
  ARNs, URLs — is kept only as a floor). Written to a per-question extract (`<id>.q.text.md`),
  rebuilt each ask; the shared cache is untouched.
- **`ccfetch`/`ccspec`/`ccexplain`/`ccexport` (no query):** there's nothing to be aware of, so only
  the salient-content regex applies — query-independent, and this is the shared **cached** extract
  (`<id>.text.md`, marker `claudius-extract v4`; a bump forces rebuild).

Then **select turns**: split each extract
into `## USER` / `## ASSISTANT` blocks; score each block by **# of distinct terms** (tiebreak: total
mentions); drop zero-match blocks; **round-robin across chats** (every chat's best block, then every
chat's 2nd-best, …) into a size budget so no chat hogs the prompt; re-order chosen blocks
chronologically per chat under `### From chat: <name>` headers.

**6 · Answer — the one real model call.** Send **only** those excerpts to `claude -p` with strict
rules: answer only from them, **cite each chat**, quote exact IDs/commands, else say `CANNOT ANSWER`.
Runs `--no-session-persistence` (creates no new chat).

## Ranking (step 4 in detail)

Computed **per term** (your words + synonyms) by `grep` over each chat's **conversation only** — a
cached user/assistant-only copy of the transcript (`<id>.conv.jsonl`). Harness-injected content
(recalled `MEMORY.md`, system-reminders — stored as `attachment` lines) is **excluded**, so a term
that a memory note repeats in every session doesn't get a falsely-high DF and lose its IDF.

- **DF → IDF presence** — `grep -lw` (whole-word: `director` ≠ `directory`) gives *which* chats contain the term (that count is the DF).
  Rarer term → higher weight `IDF = N − DF + 1`; `redrive` (in 2 of 25 chats → 24) outweighs `fix`
  (in 22 → 4). Each matching chat gets that weight once.
- **TF → topicality** — `grep -c` counts the term's matching lines. A chat that *dwells* on a term is
  "about" it even if its first message wasn't (mid-chat-drift fix); counted only above
  `CCASK_FREQ_MIN`, capped at `CCASK_FREQ_CAP`.
- **First-message boost, IDF-weighted** — if a term is in a chat's *first message*, add `w × fmult`
  (`fmult` = `CCASK_FMSG_ORIG` for your words, `CCASK_FMSG_SYN` for synonyms). Because it scales by
  the term's IDF weight `w`, opening on a **rare topical** word dominates while opening on a **common**
  word (e.g. "work") barely counts. A handoff / continuation *paste* is not a real opening topic, so
  it earns no boost — otherwise summary-seeded chats hijack every query.

Score per chat (with `w = IDF = N − DF + 1`):

```
base  = Σ_(term in first msg)  w · fmult   +   Σ_term  IDF · (1 + 0.5·min(TF, CAP))
final = base × (1 + 0.3·Recency + 0.2·Importance)
```

| Component | Weight | Per-chat value | Measures |
|---|---|---|---|
| First-message (exact) | × `CCASK_FMSG_ORIG` (100)/term | Σ `w` for your terms in the first message | opens on the topic — scaled by term rarity |
| First-message (synonym) | × `CCASK_FMSG_SYN` (40)/term | Σ `w` for synonyms in the first message | same, softer (a guessed word) |
| Presence (IDF) | ×1/term | Σ `IDF` (`N−DF+1`) per matched term | contains the term, weighted by rarity |
| Frequency topicality | × `CCASK_W_FREQ` (0.5) | Σ `min(TF,CAP)·IDF` for terms with TF ≥ `CCASK_FREQ_MIN` | how much it dwells on the term × rarity |
| Recency | × `CCASK_W_RECENCY` (0.3) | 0–1 decay by chat age | freshness — bounded tie-breaker |
| Importance | × `CCASK_W_IMPORTANCE` (0.2) | 0/1 (named/mapped chat?) | you named it — bounded tie-breaker |

Additive parts (first-message, presence, frequency) are the **relevance**; multiplicative parts
(recency, importance) are **bounded tie-breakers** (×1.0 → ×1.5) that reorder near-ties without
overriding relevance. The first-message boost being IDF-weighted (not a flat constant) is what keeps
a common opening word from hijacking the top spot.

### Recency decay

**Reciprocal (harmonic)** decay over the transcript's file age — chosen over exponential because it
needs no `exp()` (plain zsh math) and has a gentle, heavy tail so old chats fade slowly:

```
age_days = (now − transcript mtime) / 86400
recency  = 1 / (1 + age_days / τ)          τ = CCASK_RECENCY_DAYS (default 30)
```

Today → 1.00 · 7d → 0.81 · 30d (=τ) → 0.50 · 90d → 0.25 · 365d → 0.08. Bounded in (0,1]; if mtime
is unreadable, recency = 0.

## Anti-hallucination

- **No match at all** — if step 4 found zero relevant chats, `ccask` reports that **before any model
  call** (deterministic, local): nothing to send, nothing to invent.
- **Matched but insufficient** — the model, reading only the excerpts, replies `CANNOT ANSWER:` (or
  `(fully)`) rather than guessing from training. Its honesty is bounded by the retrieved text.

## Tunables

| Variable | Default | Controls |
|---|---|---|
| `CCASK_TOPK` | 5 | top-ranked chats read and sent to the answering call |
| `CCASK_EXPAND` | 1 | LLM synonym expansion (`0` = lexical only) |
| `CCASK_W_RECENCY` | 0.3 | weight of recency boost |
| `CCASK_W_IMPORTANCE` | 0.2 | weight of importance boost (named/mapped) |
| `CCASK_W_FREQ` | 0.5 | weight of term-frequency topicality |
| `CCASK_RECENCY_DAYS` | 30 | recency half-point τ (larger = slower fade) |
| `CCASK_FREQ_MIN` | 4 | min matching lines before a chat earns a frequency bonus |
| `CCASK_FREQ_CAP` | 25 | cap on counted matching lines per term |
| `CCASK_FMSG_ORIG` | 100 | first-message boost per original term (× the term's IDF weight) |
| `CCASK_FMSG_SYN` | 40 | first-message boost per synonym (× the term's IDF weight) |

IDF presence is a fixed ×1/term. The tier structure (topical-from-start ≫ synonym-topical ≫
heavy-mention ≫ mere-presence) emerges from these weights times each term's IDF.

Flags: `-c <chat>` target a chat (bare `-c` = picker) · `-s` answer from cached summaries ·
`-e`/`-E` force expansion on/off · `-r` refresh cache · `-x` print retrieved context.
