# Claudius

**Manage your Claude Code conversations by name** — resume, search, monitor, summarise, and export.

Claude Code sessions are just UUIDs. Claudius keeps a tiny Markdown *map* of
`friendly name → session id` and gives you a set of `cc*` shell commands (plus
Claude Code slash commands) to work with your conversations by name instead of
hunting for hex ids.

```
$ cclist                     # arrow-key picker (type to filter) → resume
$ ccresume "Backend Changes" # resume by name (case-insensitive, substring, tab-complete)
$ ccbranch "Backend Changes" # fork the chat's full history into a NEW session
$ ccmonitor                  # table of chats: tokens, age, working/waiting/inactive
$ ccfetch  "Backend Changes" # summarise another chat's context (via claude -p)
$ ccname                     # what's THIS chat called in the map?
```

> **zsh only.** The helpers use zsh arrays, `read -k`, glob qualifiers, and
> `compdef`. On Windows use **WSL + zsh**. Requires Claude Code (`claude` on PATH).

---

## Install

### Homebrew (macOS / Linux)
```sh
brew tap SaxenaKartik/claudius https://github.com/SaxenaKartik/claudius
brew trust saxenakartik/claudius     # one-time: recent Homebrew requires trusting third-party taps
brew install claudius
```
Then follow the two `caveats` lines Homebrew prints (source the helper; symlink the slash commands).

> **First-time trust:** recent Homebrew refuses to load formulae from untrusted third-party
> taps. If `brew install` errors with *"Refusing to load formula … from untrusted tap"*, run
> `brew trust saxenakartik/claudius` (or the per-formula `brew trust --formula saxenakartik/claudius/claudius`) and re-run install.

### Curl (macOS / Linux / WSL)
```sh
curl -fsSL https://raw.githubusercontent.com/SaxenaKartik/claudius/main/install.sh | sh
source ~/.zshrc
```

### From a clone
```sh
git clone https://github.com/SaxenaKartik/claudius && cd claudius
sh install.sh
source ~/.zshrc
```

Uninstall: `sh install.sh --uninstall` (keeps your map file).

---

## Getting started

Run **`claudius`** anytime to see this walkthrough in your terminal. The typical first run:

1. **`ccimport`** — name your existing Claude Code sessions in one pass (multi-select picker; type to filter, Space to tick, then give each a name).
2. **`cclist`** — browse and resume: type to filter, ↑/↓ to move, Enter to resume.
3. **`ccresume "My Project"`** — jump straight to a specific chat by name (case-insensitive, substring, tab-completes).
4. **Inside a chat** — `/ccname` tells you what the current chat is mapped as (`/ccadd` names it); `/ccfetch <name>` pulls another mapped chat's context into the one you're in.
5. **`ccbranch "My Project"`** — fetch a chat's *full* history and start a **new** session from it (the original is untouched).

The map itself is a plain Markdown table at `~/.claude/cc_map.md` (override with `$CC_MAP`) — edit it by hand anytime; every command reads it live.

---

## Commands

Run **`claudius`** for a getting-started walkthrough, or **`cchelp`** for the full cheat-sheet.

| Command | What it does |
|---|---|
| `cclist` | Picker: type to filter · ↑/↓ · Enter resumes · Esc clears/quits (`cclist -l` = plain list) |
| `ccresume "<name>"` | Resume by name (exact → case-insensitive → substring) |
| `ccbranch "<name>"` | Fork a chat's full history into a **new** session (original untouched) |
| `ccname` | Print THIS chat's name in the map |
| `ccplay [game]` | Mini games while something runs (guess/rps/flip/roll/react/math/hangman/scramble/8ball; no arg = menu) |
| `ccfind "<text>"` | Search names **and** notes |
| `ccimport` | Multi-select unmapped sessions (type to filter, Space ticks) → name them in |
| `ccmonitor` | Table of chats: output tokens, age, working/waiting/inactive |
| `ccfetch "<name>" [extra]` | Summarise another chat's context — **cached** (instant on repeat); `-r` to refresh; `--file x.md` for any file |
| `cccache [--clear [name]]` | List or clear the `ccfetch` summary cache |
| `ccspec "<name>" [out.md]` | Generate a spec file (goal/decisions/tasks/refs) |
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
- `/ccfetch <name>` · `/ccexplain <name>` — summarise / explain another mapped chat inline (numbered picker + confirm)
- `/ccplay [game]` — play a quick game in the chat

> Custom slash commands can't do a live keypress picker (they're prompt files, not app code). They filter **conversationally**: pass a fragment, or pick from a numbered list.

---

## How it works

- **Map file** (`~/.claude/cc_map.md`, override with `$CC_MAP`) — plain Markdown table you can hand-edit; the commands read it live.
- **Cross-workspace resume** — finds a session's transcript under any `~/.claude/projects/*/`, reads its real `cwd`, `cd`s there, then `claude --resume <id>`.
- **Config** — `CLAUDE_CONFIG_DIR` (default `~/.claude`), `CC_MAP` (default `$CLAUDE_CONFIG_DIR/cc_map.md`).

## Tests
```sh
zsh test.zsh    # isolated sandbox; 118 assertions; exit 0 = all pass
```

## License
MIT
