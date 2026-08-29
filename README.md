# Claudius

**Manage your Claude Code conversations by name** — resume, search, monitor, summarise, and **ask questions across all of them**.

Claude Code sessions are just UUIDs. Claudius keeps a tiny Markdown *map* of
`friendly name → session id` and gives you a set of `cc*` shell commands (plus
Claude Code slash commands) to work with your conversations by name instead of
hunting for hex ids — and to treat your whole chat history as a searchable memory.

```
$ cclist                       # arrow-key picker (type to filter) → resume
$ ccresume "Backend Changes"   # resume by name (case-insensitive, substring, tab-complete)
$ ccask -a "how did we fix the DLQ redrive?"   # ← ask across ALL your chats; answers + cites sources
$ ccbranch "Backend Changes"   # fork the chat's full history into a NEW session
$ ccmonitor                    # table of chats: tokens, age, working/waiting/inactive
$ ccimport --all               # name every un-named session (AI-suggested names, Enter to accept, Esc quits)
$ ccname                       # what's THIS chat called in the map?
```

> **Requires zsh + Claude Code (`claude` on `PATH`).** The helpers use zsh arrays,
> `read -k`, glob qualifiers, and `compdef`, plus zsh's own `zstat`/`strftime` modules —
> so they run identically on **macOS, Linux, and Windows (WSL)**. No Bash/PowerShell port.

---

## Install

Pick your OS below. All three routes install the same thing: a shell helper sourced from
your `~/.zshrc` and the Claude Code slash commands under `~/.claude/commands/`.

### macOS

zsh is the default shell, so nothing extra to set up.

```sh
# Homebrew
brew tap SaxenaKartik/claudius https://github.com/SaxenaKartik/claudius
brew trust saxenakartik/claudius     # one-time: recent Homebrew requires trusting third-party taps
brew install claudius
# …then follow the two caveats lines it prints (source the helper; symlink the commands).

# —or— one-line installer
curl -fsSL https://raw.githubusercontent.com/SaxenaKartik/claudius/main/install.sh | sh
source ~/.zshrc
```

> **First-time trust:** if `brew install` errors with *"Refusing to load formula … from untrusted tap"*,
> run `brew trust saxenakartik/claudius` (or `brew trust --formula saxenakartik/claudius/claudius`) and re-run.

### Linux

Install zsh if you don't have it, then use the one-line installer (or Homebrew on Linux):

```sh
sudo apt install zsh      # Debian/Ubuntu   ·   dnf install zsh (Fedora)   ·   pacman -S zsh (Arch)

curl -fsSL https://raw.githubusercontent.com/SaxenaKartik/claudius/main/install.sh | sh
source ~/.zshrc
```

The installer appends `source …/claudius.zsh` to `~/.zshrc`. If zsh isn't your login shell,
either run `zsh` first, or `chsh -s "$(command -v zsh)"` to make it default. (Homebrew on Linux
works too — same three `brew` commands as macOS.)

### Windows (WSL)

Claudius is a zsh tool, so run it inside **WSL2**, and run **Claude Code inside the same WSL
distro** so your sessions live under the Linux `~/.claude`:

```powershell
wsl --install            # in PowerShell (admin), if you don't have WSL yet — then reboot
```
```sh
# now inside your WSL shell (Ubuntu, etc.)
sudo apt update && sudo apt install zsh
curl -fsSL https://raw.githubusercontent.com/SaxenaKartik/claudius/main/install.sh | sh
source ~/.zshrc
```

> **Already run Claude Code on Windows natively (PowerShell)?** Its transcripts live at
> `C:\Users\<you>\.claude`, which WSL sees at `/mnt/c/Users/<you>/.claude`. Point Claudius there:
> `export CLAUDE_CONFIG_DIR=/mnt/c/Users/<you>/.claude` (add it to `~/.zshrc` before the source line).
> Git Bash / MSYS won't work — they're Bash, not zsh.

### From a clone (any OS)
```sh
git clone https://github.com/SaxenaKartik/claudius && cd claudius
sh install.sh
source ~/.zshrc
```

Uninstall: `sh install.sh --uninstall` (keeps your map file).

---

## Getting started

Run **`claudius`** anytime to see this walkthrough in your terminal. The typical first run:

1. **`ccimport`** — name your existing sessions in one pass. It **suggests a name** for each (from the chat's first message) — Enter accepts, type to override, `-` skips. Use **`ccimport --all`** to walk through *every* un-named chat (Esc quits at any prompt); plain `ccimport` opens a multi-select picker (Space ticks).
2. **`cclist`** — browse and resume: type to filter, ↑/↓ to move, Enter to resume.
3. **`ccresume "My Project"`** — jump straight to a specific chat by name (case-insensitive, substring, tab-completes).
4. **`ccask -a "<question>"`** — the payoff: ask anything and Claudius searches *all* your past chats, answers, and cites which ones. Or `ccask "<q>" "Chat A" "Chat B"` to scope it. Inside a chat, `/ccask <question>` does the same and lands the context in your session.
5. **Inside a chat** — `/ccname` tells you what the current chat is mapped as (`/ccadd` names it); `/ccfetch <name>` pulls another mapped chat's context into the one you're in.
6. **`ccbranch "My Project"`** — fetch a chat's *full* history and start a **new** session from it (the original is untouched).

The map itself is a plain Markdown table at `~/.claude/cc_map.md` (override with `$CC_MAP`) — edit it by hand anytime; every command reads it live.

---

## Commands

Run **`claudius`** for a getting-started walkthrough, or **`cchelp`** for the full cheat-sheet. Add **`-h`** or **`--help`** to any command (e.g. `ccfetch --help`) for its detailed usage and flags.

| Command | What it does |
|---|---|
| `cclist` | Picker: type to filter · ↑/↓ · Enter resumes · Esc clears/quits (`cclist -l` = plain list) |
| `ccresume "<name>"` | Resume by name (exact → case-insensitive → substring) |
| `ccbranch "<name>"` | Fork a chat's full history into a **new** session (original untouched) |
| `ccname` | Print THIS chat's name in the map |
| `ccplay [game]` | Mini games while something runs — **wordle** (dictionary-checked, with a live keyboard tracker), guess, rps, flip, roll, react, math, hangman, scramble, 8ball; no arg = menu |
| `ccfind "<text>"` | Search names **and** notes |
| `ccimport [-a]` | Name your un-named sessions, with an **AI-suggested name** per chat (Enter accepts · type to override · `-` skips). No flag = multi-select picker (Space ticks); `-a`/`--all` = walk through every one (Esc quits). Skips throwaway sessions. |
| `ccmonitor` | Table of chats: output tokens, age, working/waiting/inactive |
| `ccfetch "<name>" [extra]` | Summarise another chat's context — **cached** (instant on repeat); `-r` to refresh; `--file x.md` for any file |
| `ccfetch "<A>" "<B>" …` | Fetch **multiple** chats at once — per-chat use-cached / regenerate, generated in parallel, then offers to open a **new session seeded** with the combined context |
| `ccfetch` *(no arg)* | Multi-select picker (like `ccimport`): type to filter, **Space** ticks several, **Enter** fetches (Enter on one = single) |
| `ccask [-a] [-e] [-s] "<question>" [chat …]` | Ask Claude a one-shot question **about** your saved chats — headless, no new conversation. **`-a` searches across *all* your chats**, ranks them by relevance (+ recency/importance tie-breakers), answers from the top few, and **cites which chats** it used. **`-e`** (with `-a`) widens recall: Claude first suggests **synonyms/abbreviations** for your query (e.g. *dead-letter queue* → also `dlq`, `redrive`) and searches those too — semantic recall with no embeddings (`$CCASK_EXPAND=1` to make it default). Without `-a`, answers from the named/picked chat(s) — reading the **full transcript** (`-s` = the cheaper cached summaries). Replies `CANNOT ANSWER:` if the chats don't cover it. On a terminal the answer is **rendered with styling** and offers to **copy the raw markdown**. |
| `cccache [--clear [name]]` | List or clear the summary cache (both `ccfetch` and `ccspec`, shown with a TYPE column) |
| `cccleanup [-y]` | Delete Claudius's own headless `claude -p` runs that got recorded as chats (they clutter history and pollute `ccask -a`). New asks won't be recorded — Claudius runs `claude -p --no-session-persistence`. |
| `ccspec "<name>" [out.md]` | Generate a spec file (goal/decisions/tasks/refs) — writes it **and** prints it; **cached** (instant on repeat); `-r` to refresh |
| `ccexplain "<name>"` | Plain-terms Done / Pending / Next |
| `ccexport "<name>" [out.md]` | Write a context markdown file |
| `ccadd "<name>" [id] ["notes"]` | Add a row (id defaults to the current session) |
| `ccnote "<name>" "<notes>"` | Replace an entry's notes |
| `ccrename "<old>" "<new>"` | Rename a key (session id preserved) |
| `ccremove [-y] "<name>"` | Remove a row |
| `cchelp` | Usage cheat-sheet |
| `claudius` | Getting-started walkthrough |

**Any name-taking command with no argument opens the filter-picker.** Names also
**tab-complete** (case-insensitive substring).

### Slash commands (inside a Claude Code chat)
- `/ccadd [name]` — add the current chat to the map
- `/ccname` — show the current chat's mapped name
- `/ccspec [path]` · `/ccexport [path]` — write a spec / context file for the current chat
- `/ccfetch <name(s)>` — pull one **or several** mapped chats' context into the current session (per-chat use-cached / regenerate; regenerated in parallel via subagents)
- `/ccask <question>` — answer a question using your **other** chats: retrieves the most relevant excerpts across all your sessions (locally, no nested model call) and answers **in this chat, with citations**
- `/ccexplain <name>` — explain another mapped chat inline (numbered picker + confirm)
- `/ccplay [game]` — play a quick game in the chat

> Custom slash commands can't do a live keypress picker (they're prompt files, not app code). They filter **conversationally**: pass a fragment, or pick from a numbered list.

---

## How it works

- **Map file** (`~/.claude/cc_map.md`, override with `$CC_MAP`) — plain Markdown table you can hand-edit; the commands read it live.
- **Cross-workspace resume** — finds a session's transcript under any `~/.claude/projects/*/`, reads its real `cwd`, `cd`s there, then `claude --resume <id>`.
- **Cross-chat ask (`ccask -a`)** — retrieval is done **locally**: rank every session by relevance (keyword hits, IDF-weighted so rare words like a project name outweigh common ones, plus a boost for chats whose *first message* matches), then break near-ties by **recency** (older chats decay smoothly) and **importance** (chats you named/mapped rank higher) — a bounded, multiplicative bonus, so a clearly more-relevant chat always still wins. Then pull focused excerpts from the top few (round-robin so no single chat hogs the budget) and make **one** `claude -p` call to answer with citations. Tunable via `$CCASK_W_RECENCY`, `$CCASK_W_IMPORTANCE`, `$CCASK_RECENCY_DAYS`.
- **Semantic recall without embeddings (`ccask -a -e`)** — instead of a vector database, Claudius borrows Claude's semantic knowledge *once*: it expands your query into synonyms/abbreviations (*dead-letter queue* → `dlq`, `redrive`, `sqs`, `reprocess`) and feeds those into the same free local lexical ranker. You get meaning-based recall — finding a chat that used different words than your question — with no embedding model, vector store, or extra dependency. (True embeddings/RAPTOR remain a future option for larger histories.)
- **Compact-but-lossless extract** — transcripts are read from a cached text extract (~100× smaller than the raw JSONL, which is mostly tool/metadata noise), never the whole file. The extract keeps the parts that matter for answering: message text, the **inputs** of each tool call (the command/query/path/URL you actually ran), the head **and** tail of long tool results, and a short slice of reasoning — so `ccask` can tell you *what* command fixed something, not just *that* a tool ran.
- **Clean corpus** — Claudius's own headless `claude -p` runs pass `--no-session-persistence`, so they aren't recorded as chats; ephemeral sessions (one-shots, `ccfetch` seed sessions, slash-command runs) are excluded from search and import; `cccleanup` removes any legacy ones.
- **Config** — `CLAUDE_CONFIG_DIR` (default `~/.claude`), `CC_MAP` (default `$CLAUDE_CONFIG_DIR/cc_map.md`), `CCASK_TOPK` (how many chats `ccask -a` reads, default 5).

## Tests
```sh
zsh test.zsh    # isolated sandbox; 150+ assertions; exit 0 = all pass
```

## License
MIT
