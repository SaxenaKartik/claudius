# Claudius — manage Claude Code conversations by name (reads the session map)
#   claudius                      getting-started walkthrough
# Enable by adding to ~/.zshrc:  source ~/.claude/claudius.zsh
#
#   ccname                        print THIS chat's name in the map (uses $CLAUDE_CODE_SESSION_ID)
#   ccplay [game]                 mini games while Claude thinks (no arg = menu; wordle/guess/rps/flip/roll/react/math/hangman/scramble/8ball)
#   cclist                        interactive picker (type to filter, ↑/↓, Enter resumes, Esc clear/quit; -l = plain list)
#   ccresume "<name>"             resume by name (exact -> case-insensitive -> substring; no arg opens picker)
#   ccbranch "<name>"             fork a chat's full history into a NEW session (original untouched)
#   ccfind "<text>"               search names + notes for a substring
#   ccimport                      pick unmapped sessions (multi-select) and name them into the map
#   ccmonitor [N]                 table of recent chats: tokens (out/ctx), age, status (working/waiting/inactive)
#   ccfetch "<name>" [extra]      summarise another chat's context (cached; -r to refresh; --file <p> for a file)
#   ccfetch "<A>" "<B>" …         fetch MULTIPLE chats at once (per-chat use/regenerate, parallel; offers a new seeded session)
#   ccfetch                       (no arg) multi-select picker — type to filter, Space ticks several, Enter fetches
#   ccask [-a] "<q>" [chat …]     ask Claude about your chats, headless: -a = across ALL chats (ranked + cited); else named/picked chats; -s = from summaries
#   cccache [--clear [name]]      list / clear the ccfetch summary cache
#   cccleanup [-y]                delete Claudius's own headless claude -p runs recorded as chats
#   ccspec "<name>" [out.md]      write a spec file (goal/decisions/tasks/refs) for a chat
#   ccexplain "<name>" [extra]    explain a chat in plain terms: Done / Pending / Next
#   ccexport "<name>" [out.md]    write a context markdown file (overview/what happened/decisions/refs)
#   ccnote "<name>" "<notes>"     replace the notes column of an entry
#   ccadd "<name>" [<id>] [notes] add a row (id defaults to $CLAUDE_CODE_SESSION_ID inside a session)
#   ccrename "<old>" "<new>"      rename a key (session id preserved; resume trigger follows automatically)
#   ccremove [-y] "<name>"        remove a row (confirms; refuses ambiguous matches)
#   cchelp                        show this usage summary
# Tab completion: ccresume/ccremove/ccrename/ccnote/ccfetch/ccspec/ccfind complete conversation names (needs compinit loaded).
_CC_MAP="${CC_MAP:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cc_map.md}"

# Signature of Claudius' OWN headless `claude -p` runs (matched on a session's FIRST user message).
# Used to keep them out of ccask's search corpus and to let `cccleanup` delete them.
_CC_INTERNAL_SIG='You are answering from excerpts of MULTIPLE|Answer the question strictly and specifically|Answer the question using ONLY the conversation summaries|Read the following [A-Za-z ]{0,30}transcript|Read the Claude Code (session|conversation) transcript|Read the document at.*produce a concise summary|Write a Markdown CONTEXT EXPORT|write a SPEC document in Markdown|explain it in simple, plain terms|Suggest a concise 2'
_cc_is_internal() {   # 0 if $1 is a Claudius-generated headless session (by its first user message)
  grep -m1 '"type":"user"' "$1" 2>/dev/null | grep -qE "$_CC_INTERNAL_SIG"
}
_cc_is_ephemeral() {  # 0 if $1 is a throwaway session not worth importing/searching:
  # a one-shot (<=1 user turn: headless claude -p, slash-command one-off, or abandoned) OR a
  # "new session seeded with summaries" session. Robust & wording-independent.
  local nu; nu=$(LC_ALL=C grep -c -m2 '"type":"user"' "$1" 2>/dev/null)
  (( ${nu:-0} <= 1 )) && return 0
  local fm; fm=$(grep -m1 '"type":"user"' "$1" 2>/dev/null)
  print -r -- "$fm" | grep -q "starting a new working session. Below are handoff" && return 0
  print -r -- "$fm" | grep -qF '<command-name>/cc' && return 0   # session opened with a Claudius slash command
  return 1
}

# Portable file-time helpers — macOS/BSD `stat -f` and GNU `stat -c` are incompatible,
# so prefer zsh's own modules (work identically on macOS, Linux, and WSL).
zmodload -F zsh/stat b:zstat 2>/dev/null   # provides zstat (portable mtime)
zmodload zsh/datetime 2>/dev/null          # provides strftime / EPOCHSECONDS
_cc_mtime() {        # epoch mtime of $1 (empty on failure)
  local -a st
  if zstat -A st +mtime -- "$1" 2>/dev/null; then print -r -- "$st[1]"; return; fi
  stat -f %m -- "$1" 2>/dev/null || stat -c %Y -- "$1" 2>/dev/null   # BSD then GNU fallback
}
_cc_mtime_fmt() {    # mtime of $1 as "YYYY-mm-dd HH:MM" (empty on failure)
  local e; e=$(_cc_mtime "$1"); [[ -z $e ]] && return
  if (( ${+builtins[strftime]} )); then strftime '%Y-%m-%d %H:%M' "$e"
  else date -r "$e" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$e" '+%Y-%m-%d %H:%M' 2>/dev/null; fi
}

_cc_help() {   # detailed per-command help shown by `<cmd> -h|--help`
  local c="${1-}"
  case "$c" in
    claudius)  print -r -- 'claudius — print the getting-started walkthrough.
  Usage: claudius
  No flags. See cchelp for the full command cheat-sheet.';;
    cchelp)    print -r -- 'cchelp — print the full command cheat-sheet.
  Usage: cchelp
  No flags. Add -h (or --help) to any command for its own detailed help.';;
    cclist)    print -r -- 'cclist — interactive picker to resume a chat by name.
  Usage: cclist [-l|--list]
  Keys: type to filter, up/down to move, Enter resumes, Esc clears then quits.
  Flags:
    -l, --list   print a plain list instead of the picker (also used when not a TTY).';;
    ccresume)  print -r -- 'ccresume — resume a mapped chat by name.
  Usage: ccresume "<name>"
  Match: exact (case-insensitive), then substring. With no argument, opens the cclist picker.
  Resolves the original working directory of the session from its transcript and runs
  claude --resume there, so it works across workspaces. Names tab-complete.';;
    ccbranch)  print -r -- 'ccbranch — fork the full history of a chat into a NEW session.
  Usage: ccbranch "<name>"
  Runs claude --resume <id> --fork-session; the original conversation is left untouched.
  With no argument, opens the picker.';;
    ccfind)    print -r -- 'ccfind — search the map by text.
  Usage: ccfind "<text>"
  Case-insensitive substring match over conversation NAMES and NOTES.';;
    ccmonitor) print -r -- 'ccmonitor — status table of all mapped chats.
  Usage: ccmonitor
  Columns: name, output tokens (summed from the transcript), age, and state
  (working <30s, waiting <5m, inactive). No flags.';;
    ccfetch)   print -r -- 'ccfetch — summarise the context of another chat (read-only; never resumes it).
  Usage:
    ccfetch "<name>" [extra]     summarise one mapped chat (cached; instant on repeat)
    ccfetch "<A>" "<B>" ...      fetch SEVERAL chats: per-chat use/regenerate, generated in
                                 parallel, prints the combined context, then offers to open a
                                 new session seeded with it
    ccfetch                      no argument: multi-select picker (Space ticks several, Enter fetches)
    ccfetch --file <path.md>     summarise an arbitrary file instead (shorthand: @path.md)
  Flags:
    -r, --refresh                regenerate the cached summary (one chat, or all in multi mode)
    [extra]                      extra instructions appended to the prompt (single mode; not cached)
  Cache: <config>/claudius-cache/<id>.fetch.md — manage it with cccache.';;
    ccask)     print -r -- 'ccask — ask Claude a one-shot question about your saved chats (headless; no new conversation).
  Usage: ccask [-a] [-s] [-r] "<question>" [<chat> ...]
  -a, --all       search ACROSS ALL your chats — ranks every session by relevance, answers from the
                  top few, and CITES which chats it used. No need to name a chat. (top N via $CCASK_TOPK, default 5)
  Otherwise resolves each named chat by name (exact -> substring). By DEFAULT reads the transcript(s) as a compact
  TEXT extract (the raw JSONL is ~97% tool/metadata noise; the extract is ~30x smaller, so it is
  fast) and answers strictly from them — a live spinner shows progress. Best fidelity; sees detail
  that summaries drop. No chats named -> multi-select picker. If the answer is not in the chats it
  replies starting "CANNOT ANSWER:" instead of inventing one.
  Flags:
    -s, --summary   answer from the cached handoff summaries instead (fast/cheap, but lossy).
    -r, --refresh   with -s, regenerate the summaries first.
  On a TTY the answer is rendered with styling (glow if installed, else a built-in renderer) and
  then offers to copy the raw markdown to your clipboard. Piped/redirected output stays raw markdown.';;
    cccache)   print -r -- 'cccache — manage the ccfetch/ccspec summary cache.
  Usage:
    cccache [-l|--list]          list cached summaries (TYPE column shows fetch or spec)
    cccache --clear [name]       clear every cache, or only the chat matching <name>
  Flags: -l, --list   list (default);   -c, --clear   clear.';;
    cccleanup) print -r -- 'cccleanup — delete Claudius'\''s own headless `claude -p` runs that got recorded as chats.
  Usage: cccleanup [-y]
  ccfetch/ccask/ccspec/… each run `claude -p`, which used to leave a throwaway session transcript;
  those clutter your history and pollute ccask -a. This finds them (by their prompt signature in the
  first message) and deletes them. -y skips the confirm. Going forward Claudius passes
  --no-session-persistence so no new ones are created.';;
    ccspec)    print -r -- 'ccspec — generate a SPEC document from the transcript of a chat.
  Usage: ccspec [-r] "<name>" [output.md]
  Writes the spec to <output.md> (default ./<slug>.spec.md) AND prints it.
  Sections: Goal/Context, Key Decisions, Tasks (checkboxes), Open Questions, References.
  Cached (instant on repeat) at <config>/claudius-cache/<id>.spec.md.
  Flags:
    -r, --refresh   regenerate the cached spec.   With no name, opens the picker.';;
    ccexplain) print -r -- 'ccexplain — plain-terms Done / Pending / Next for a chat.
  Usage: ccexplain "<name>" [extra]
  Prints a short status to stdout (not cached). With no name, opens the picker.';;
    ccexport)  print -r -- 'ccexport — write a Markdown context export for handoff.
  Usage: ccexport "<name>" [output.md]
  Default path ./<slug>.context.md. Sections: Overview, What happened, Decisions,
  Current state, References. With no name, opens the picker.';;
    ccnote)    print -r -- 'ccnote — set the notes column for a mapped chat.
  Usage: ccnote "<name>" "<new notes>"
  Replaces (does not append) the notes. Refuses ambiguous name matches.';;
    ccimport)  print -r -- 'ccimport — name your UNMAPPED on-disk sessions into the map.
  Usage: ccimport [-a|--all]
  -a, --all  skip the picker and walk through EVERY unmapped session (Enter accepts each suggestion, "-" skips, Esc quits).
  Multi-select picker of sessions not yet in the map: type to filter, up/down, Space ticks,
  Enter confirms, Esc quits. Preview = date, workspace, first user message. For each pick it
  SUGGESTS a name (via claude, from the chat first message) — Enter accepts it, type to override,
  "-" skips — then adds each with ccadd.';;
    ccremove)  print -r -- 'ccremove — delete a row from the map.
  Usage: ccremove [-y] "<name>"
  Confirms first and refuses ambiguous matches. With no name, opens the picker.
  Flags:
    -y   skip the confirmation prompt.';;
    ccadd)     print -r -- 'ccadd — add a row to the map.
  Usage: ccadd "<name>" [<session-id>] ["<notes>"]
  <session-id> defaults to $CLAUDE_CODE_SESSION_ID (the current chat).
  Refuses duplicate names/ids and malformed UUIDs. A name cannot contain | or a backtick.';;
    ccrename)  print -r -- 'ccrename — rename a mapped chat (the session id is preserved).
  Usage: ccrename "<old name>" "<new name>"
  The resume trigger follows the new name because the map is read live.
  With no <old name>, opens the picker.';;
    ccname)    print -r -- 'ccname — print what THIS chat is mapped as.
  Usage: ccname
  Looks up $CLAUDE_CODE_SESSION_ID in the map. No flags.';;
    ccplay)    print -r -- 'ccplay — mini games to pass the time (no session impact).
  Usage: ccplay [game]
  Games: wordle, guess, rps, flip, roll, react, math, hangman, scramble, 8ball.
  With no argument, shows the menu.';;
    *)         print -r -- "no help available for '$c'"; return 1;;
  esac
}

claudius() {   # getting-started walkthrough
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help claudius; return 0; }
  print -r -- $'\e[1mClaudius\e[0m \e[2m— manage your Claude Code conversations by name\e[0m'
  print -r -- $'\e[2mClaude Code sessions are opaque UUIDs; Claudius maps friendly names to them.\e[0m'
  print
  print -r -- $'\e[1mGetting started\e[0m'
  printf '  \e[2m1.\e[0m \e[36m%-22s\e[0m %s\n' 'ccimport'              'name your existing sessions in one pass (multi-select)'
  printf '  \e[2m2.\e[0m \e[36m%-22s\e[0m %s\n' 'cclist'                'browse & resume — type to filter · ↑/↓ · Enter'
  printf '  \e[2m3.\e[0m \e[36m%-22s\e[0m %s\n' 'ccresume "My Project"' 'resume a specific chat by name'
  printf '  \e[2m4.\e[0m \e[36m%-22s\e[0m %s\n' '/ccname   (in a chat)' 'what'\''s THIS chat called?   (/ccadd to name it)'
  printf '     \e[36m%-22s\e[0m %s\n'           '/ccfetch  (in a chat)' 'pull another chat'\''s context into the current one'
  printf '  \e[2m5.\e[0m \e[36m%-22s\e[0m %s\n' 'ccbranch "My Project"' 'fetch a chat'\''s full context, then start a NEW session'
  print
  print -r -- "  map file:      $_CC_MAP"
  print -r -- $'  all commands:  run \e[36mcchelp\e[0m'
  print -r -- $'  in a chat:     /ccadd /ccname /ccfetch /ccspec /ccexplain /ccexport'
  print -r -- $'  \e[2mdocs: https://github.com/SaxenaKartik/claudius\e[0m'
}

cchelp() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help cchelp; return 0; }
  print -r -- $'\e[1mClaudius\e[0m — manage Claude Code conversations by name'
  print -r -- "  map: $_CC_MAP"
  print
  printf '  \e[36m%-33s\e[0m %s\n' 'ccname'                        'print THIS chat'\''s name in the map'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccplay [game]'                 'mini games while Claude thinks (no arg = menu)'
  printf '  \e[36m%-33s\e[0m %s\n' 'cclist'                        'picker: type to filter · ↑/↓ · Enter resume · Esc clear/quit'
  printf '  \e[36m%-33s\e[0m %s\n' 'cclist -l'                     'plain list (name + id)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccresume "<name>"'             'resume by name (exact → case-insensitive → substring)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccbranch "<name>"'             'fork a chat'\''s full history into a NEW session'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccfind "<text>"'               'search names + notes for a substring'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccimport'                      'multi-select unmapped sessions → name them into the map'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccmonitor [N]'                 'table of recent chats: tokens, age, status'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccfetch "<name>" [extra]'      'summarise another chat (cached; -r refresh; --file <p>)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccfetch "<A>" "<B>" …'         'fetch MULTIPLE chats at once (per-chat use/regen, parallel)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccask [-a] "<q>" [chat …]'      'ask Claude about your chats: -a = across ALL (ranked+cited); else named; -s = summaries'
  printf '  \e[36m%-33s\e[0m %s\n' 'cccache [--clear]'             'list / clear the ccfetch/ccspec summary cache'
  printf '  \e[36m%-33s\e[0m %s\n' 'cccleanup [-y]'                'remove Claudius'\''s own claude -p runs recorded as chats'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccspec "<name>" [out.md]'      'write a spec file (goal/decisions/tasks) for a chat'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccexplain "<name>" [extra]'    'plain-terms explanation: Done / Pending / Next'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccexport "<name>" [out.md]'    'write a context markdown file for a chat'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccnote "<name>" "<notes>"'     'replace an entry'\''s notes'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccadd "<name>" [id] ["notes"]' 'add a row (id defaults to $CLAUDE_CODE_SESSION_ID)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccrename "<old>" "<new>"'      'rename a key (session id preserved)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccremove [-y] "<name>"'        'remove a row (confirms; refuses ambiguous)'
  printf '  \e[36m%-33s\e[0m %s\n' 'cchelp'                        'show this help'
  printf '  \e[36m%-33s\e[0m %s\n' 'claudius'                      'getting-started walkthrough'
  print
  print -r -- $'  \e[2mIn a chat: /ccadd /ccname /ccfetch /ccspec /ccexplain /ccexport\e[0m'
  print -r -- $'  \e[2mPickers (cclist, ccimport, any name cmd with no arg): type to filter · ↑/↓ · Esc clears\e[0m'
  print -r -- $'  \e[2mAdd -h or --help to any command for detailed usage and flags.\e[0m'
}

# Resolve the workspace/cwd a session belongs to (Claude scopes --resume by cwd).
_cc_cwd_for_id() {
  local id="${1-}" proj cwd f
  local -a matches
  matches=( "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"/*/"$id.jsonl"(N) )   # search ALL workspaces
  (( ${#matches} == 0 )) && return 1
  f=${matches[1]}
  cwd=$(grep -o '"cwd":"[^"]*"' "$f" 2>/dev/null | head -1 | sed 's/^"cwd":"//; s/"$//')  # authoritative, dash-proof
  if [[ -z $cwd || ! -d $cwd ]]; then
    proj=${${f:h}:t}; cwd=${proj//-//}   # fallback: decode dir name
  fi
  [[ -d $cwd ]] && { print -r -- "$cwd"; return 0; }
  return 1
}

_cc_launch() {
  local id="${1-}"; shift 2>/dev/null || true
  local -a extra=("$@")            # optional extra flags (e.g. --fork-session)
  local cwd; cwd=$(_cc_cwd_for_id "$id")
  if [[ -n $cwd && $cwd != $PWD ]]; then
    echo "(cd $cwd) claude --resume $id ${extra[*]}"
    (cd "$cwd" && claude --resume "$id" "${extra[@]}")
  else
    claude --resume "$id" "${extra[@]}"
  fi
}

_cc_rows() {
  awk -F'|' '
    /^\|/ && /`/ {
      name=$2; id=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",name);
      gsub(/[`[:space:]]/,"",id);
      if (length(id)==36 && id ~ /^[0-9a-f-]+$/) print name "\t" id;
    }' "$_CC_MAP" 2>/dev/null
}

_cc_plain() { _cc_rows | awk -F'\t' '{printf "  \033[36m%s\033[0m  \033[2m%s\033[0m\n",$1,$2}'; }

_cc_pick() {
  local -a names ids
  local name id
  while IFS=$'\t' read -r name id; do names+=("$name"); ids+=("$id"); done < <(_cc_rows)
  (( ${#names} == 0 )) && { print -u2 "No conversations in the map ($_CC_MAP)."; return 1; }
  local filter="" key seq sel=1 drawn=0 cancelled=
  local -a fidx
  local _recompute _draw
  _recompute() {   # rebuild filtered index list; clamp selection
    fidx=(); local i lf="${filter:l}"
    for (( i=1; i<=${#names}; i++ )); do
      [[ -z $lf || "${names[i]:l}" == *"$lf"* ]] && fidx+=($i)
    done
    (( sel < 1 )) && sel=1
    if (( ${#fidx} == 0 )); then sel=0; elif (( sel > ${#fidx} )); then sel=${#fidx}; fi
  }
  _draw() {
    (( drawn > 0 )) && printf '\e[%dA\r\e[J' "$drawn" >&2      # rewind + clear (list may shrink)
    printf '\e[1mfilter:\e[0m %s\e[7m \e[0m  \e[2m(type · ↑/↓ · Enter · Esc clear/quit)\e[0m\n' "$filter" >&2
    local shown=1 j real
    if (( ${#fidx} == 0 )); then
      printf '  \e[2m(no matches)\e[0m\n' >&2; (( shown++ ))
    else
      for (( j=1; j<=${#fidx}; j++ )); do
        real=${fidx[j]}
        if (( j == sel )); then printf '  \e[1;32m▶ %s\e[0m\n' "${names[real]}" >&2
        else printf '    \e[36m%s\e[0m\n' "${names[real]}" >&2; fi
        (( shown++ ))
      done
    fi
    drawn=$shown
  }
  tput civis 2>/dev/null
  _recompute; _draw
  while true; do
    read -rsk1 key
    case $key in
      $'\e') seq=''; read -rsk2 -t 0.4 seq 2>/dev/null   # reset so a lone Esc isn't mistaken for a stale arrow
        case $seq in
          '[A'|'OA') (( sel > 1 )) && (( sel-- ));;
          '[B'|'OB') (( sel < ${#fidx} )) && (( sel++ ));;
          '') if [[ -n $filter ]]; then filter=""; sel=1; _recompute; else cancelled=1; break; fi;;
        esac;;
      $'\n'|$'\r') (( ${#fidx} >= 1 )) && break;;
      $'\x7f'|$'\b') filter="${filter%?}"; sel=1; _recompute;;
      *) [[ $key == [[:print:]] ]] && { filter+="$key"; sel=1; _recompute; };;
    esac
    _draw
  done
  tput cnorm 2>/dev/null
  [[ -n $cancelled ]] && { print -u2 "cancelled"; return 1; }
  local chosen=${fidx[sel]}
  _CC_PICKED_ID=${ids[chosen]}; _CC_PICKED_NAME=${names[chosen]}   # return via globals, never $(...)
  return 0
}

cclist() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help cclist; return 0; }
  if [[ "${1-}" == "-l" || "${1-}" == "--list" ]]; then _cc_plain; return; fi
  if [[ ! -t 0 || ! -t 1 ]]; then _cc_plain; return; fi   # not a TTY -> plain list
  _CC_PICKED_ID=; _CC_PICKED_NAME=
  _cc_pick || return 1                                    # runs in THIS shell, not $(...)
  [[ -n $_CC_PICKED_ID ]] && _cc_launch "$_CC_PICKED_ID"
}

_ccplay_guess() {   # Hi-Lo number guessing
  local target=$(( RANDOM % 100 + 1 )) guess tries=0 word
  while true; do
    read "guess?  > " || { printf '  it was %d — later!\n' "$target"; return 0; }
    [[ "$guess" == (q|Q|quit) ]] && { printf '  it was \e[1m%d\e[0m — later!\n' "$target"; return 0; }
    if [[ "$guess" != <-> ]]; then printf '  \e[2m(numbers only)\e[0m\n'; continue; fi
    (( tries++ ))
    if   (( guess < target )); then printf '  \e[33m↑ higher\e[0m\n'
    elif (( guess > target )); then printf '  \e[36m↓ lower\e[0m\n'
    else word=tries; (( tries == 1 )) && word=try; printf '  \e[1;32m🎉 %d in %d %s!\e[0m\n' "$target" "$tries" "$word"; return 0; fi
  done
}
_ccplay_rps() {     # rock-paper-scissors
  local -a o=(rock paper scissors); local you comp res
  read "you?  r/p/s: " || return 0
  case ${you:l} in r*) you=rock;; p*) you=paper;; s*) you=scissors;; *) printf '  (didn'\''t get that)\n'; return 0;; esac
  comp=${o[RANDOM % 3 + 1]}
  if [[ $you == $comp ]]; then res=$'\e[2mtie\e[0m'
  elif [[ ($you == rock && $comp == scissors) || ($you == paper && $comp == rock) || ($you == scissors && $comp == paper) ]]; then res=$'\e[1;32myou win 🎉\e[0m'
  else res=$'\e[31myou lose\e[0m'; fi
  printf '  you: %s · me: %s → %s\n' "$you" "$comp" "$res"
}
_ccplay_flip() { (( RANDOM % 2 )) && printf '  🪙 Heads\n' || printf '  🪙 Tails\n'; }
_ccplay_roll() { local a=$((RANDOM%6+1)) b=$((RANDOM%6+1)); printf '  🎲 %d + %d = \e[1m%d\e[0m\n' "$a" "$b" "$(( a + b ))"; }
_ccplay_react() {   # reaction timer
  zmodload zsh/datetime 2>/dev/null || { printf '  (reaction game needs the zsh/datetime module)\n'; return 1; }
  print -n -- "  press any key to start…"; read -k1 -s; print
  sleep $(( (RANDOM % 2500 + 800) / 1000.0 ))
  local t0=$EPOCHREALTIME
  printf '  \e[1;32mGO — hit a key!\e[0m '
  read -k1 -s; print
  printf '  \e[1m%.0f ms\e[0m\n' $(( (EPOCHREALTIME - t0) * 1000 ))
}
_ccplay_math() {    # quick arithmetic quiz
  local n=5 correct=0 i a b op want ans
  for (( i=1; i<=n; i++ )); do
    a=$((RANDOM%12+1)); b=$((RANDOM%12+1))
    case $((RANDOM%3)) in 0) op='+'; want=$((a+b));; 1) op='-'; want=$((a-b));; 2) op='×'; want=$((a*b));; esac
    read "ans?  Q$i:  $a $op $b = " || break
    if [[ "$ans" == "$want" ]]; then printf '  \e[1;32m✓\e[0m\n'; (( correct++ ))
    else printf '  \e[31m✗  (= %d)\e[0m\n' "$want"; fi
  done
  printf '  score: \e[1m%d/%d\e[0m\n' "$correct" "$n"
}
_ccplay_hangman() { # guess the word letter by letter
  local -a words=(claude terminal session resume conversation keyboard function shuffle monkey planet)
  local word=${words[RANDOM % ${#words} + 1]}
  local -a revealed; local i; for (( i=1; i<=${#word}; i++ )); do revealed[i]='_'; done
  local misses=0 max=7 guessed="" g disp hit
  while (( misses < max )); do
    disp=""; for (( i=1; i<=${#word}; i++ )); do disp+="${revealed[i]} "; done
    if [[ "$disp" != *'_'* ]]; then printf '  %s  \e[1;32m🎉\e[0m\n' "$disp"; return 0; fi
    printf '  %s  \e[2m(misses %d/%d%s)\e[0m\n' "$disp" "$misses" "$max" "${guessed:+; tried: $guessed}"
    read "g?  letter (q quits): " || break
    [[ "$g" == (q|Q) ]] && { printf '  it was \e[1m%s\e[0m\n' "$word"; return 0; }
    g=${g:l}; g=${g[1]}
    [[ "$g" == [a-z] ]] || { printf '  \e[2m(one letter, please)\e[0m\n'; continue; }
    [[ "$guessed" == *"$g"* ]] && { printf '  \e[2m(already tried %s)\e[0m\n' "$g"; continue; }
    guessed+="$g"
    hit=0; for (( i=1; i<=${#word}; i++ )); do [[ "${word[i]}" == "$g" ]] && { revealed[i]=$g; hit=1; }; done
    (( hit )) || (( misses++ ))
  done
  printf '  \e[31mout of guesses — it was %s\e[0m\n' "$word"
}
_ccplay_scramble() {  # unscramble the word
  local -a words=(puzzle rocket garden pixel coffee guitar planet dragon castle wizard)
  local word=${words[RANDOM % ${#words} + 1]}
  local -a chars=(${(s::)word}); local i j tmp
  for (( i=${#chars}; i>1; i-- )); do j=$(( RANDOM % i + 1 )); tmp=${chars[i]}; chars[i]=${chars[j]}; chars[j]=$tmp; done
  printf '  unscramble:  \e[1m%s\e[0m\n' "${(j::)chars}"
  local ans; read "ans?  > " || return 0
  if [[ "${ans:l}" == "$word" ]]; then printf '  \e[1;32m🎉 correct!\e[0m\n'
  else printf '  \e[31mnope — it was %s\e[0m\n' "$word"; fi
}
_ccplay_8ball() {   # magic 8-ball
  local -a a=("It is certain." "Without a doubt." "Yes — definitely." "Most likely." "Signs point to yes."
              "Reply hazy, try again." "Ask again later." "Cannot predict now." "Don't count on it."
              "My reply is no." "Very doubtful." "Outlook not so good.")
  local q; read "q?  🎱 ask a yes/no question: " || return 0
  printf '  \e[1m%s\e[0m\n' "${a[RANDOM % ${#a} + 1]}"
}
_ccplay_wordle_kb() {   # draw the QWERTY key tracker (reads assoc array `kb` via zsh dynamic scope)
  local -a rows=(qwertyuiop asdfghjkl zxcvbnm) indent=('' '  ' '      ')
  local i c ch out
  for (( i=1; i<=3; i++ )); do
    out="  ${indent[i]}"
    for c in ${(s::)rows[i]}; do
      ch=${(U)c}
      case ${kb[$c]-} in
        G) out+=$'\e[48;5;34;38;5;231m '"$ch"$' \e[0m ';;    # right spot  (green key)
        Y) out+=$'\e[48;5;178;38;5;16m '"$ch"$' \e[0m ';;    # in word     (gold key)
        X) out+=$'\e[48;5;238;38;5;245m '"$ch"$' \e[0m ';;   # used/absent (dark key)
        *) out+=$'\e[48;5;250;38;5;16m '"$ch"$' \e[0m ';;    # unused      (light key)
      esac
    done
    print -u2 -- "$out"
  done
}
_ccplay_wordle() {  # Wordle — 5-letter word, 6 tries, colored tiles + used-letter keyboard, dictionary-checked
  local -a words=(crane slate plumb ghost mirth blaze cider fjord query vivid
         mango pluck zebra ivory nudge frost gleam brisk chalk dwarf
         epoxy flick gruel hoist jolly knelt lyric mound noble ocean
         pride quilt raven shine trove usher wharf yacht amber blush)
  local word=${words[RANDOM % ${#words} + 1]}
  local dict=; local d; for d in /usr/share/dict/words /usr/dict/words; do [[ -r $d ]] && { dict=$d; break; }; done
  local max=6 n=0 guess i
  local -A kb rank=(G 3 Y 2 X 1)
  _ccplay_wordle_kb
  while (( n < max )); do
    read "guess?  [$((n+1))/$max] > " || { printf '  the word was \e[1m%s\e[0m\n' "$word"; return 0; }
    guess=${guess:l}
    [[ "$guess" == (q|Q|quit) ]] && { printf '  the word was \e[1m%s\e[0m\n' "$word"; return 0; }
    if [[ "$guess" != [a-z][a-z][a-z][a-z][a-z] ]]; then printf '  \e[2m(type exactly 5 letters, a–z)\e[0m\n'; continue; fi
    if [[ -n $dict && "$guess" != "$word" ]] && ! LC_ALL=C grep -qix -- "$guess" "$dict"; then
      printf '  \e[2m(“%s” is not in the word list — try a real word)\e[0m\n' "$guess"; continue
    fi
    local -a tgt=(${(s::)word}) gss=(${(s::)guess}) mark=()
    local -A avail=(); for i in {1..5}; do avail[${tgt[i]}]=$(( ${avail[${tgt[i]}]:-0} + 1 )); done
    for i in {1..5}; do                                   # pass 1: greens (exact position)
      if [[ ${gss[i]} == ${tgt[i]} ]]; then mark[i]=G; avail[${gss[i]}]=$(( avail[${gss[i]}] - 1 )); else mark[i]=.; fi
    done
    for i in {1..5}; do                                   # pass 2: yellows (present) vs grays
      [[ ${mark[i]} == G ]] && continue
      if (( ${avail[${gss[i]}]:-0} > 0 )); then mark[i]=Y; avail[${gss[i]}]=$(( avail[${gss[i]}] - 1 )); else mark[i]=X; fi
    done
    local row="" ch=""
    for i in {1..5}; do
      ch=${(U)gss[i]}
      case ${mark[i]} in
        G) row+=$'\e[48;5;34;38;5;231m '"$ch"$' \e[0m ';;
        Y) row+=$'\e[48;5;178;38;5;16m '"$ch"$' \e[0m ';;
        X) row+=$'\e[48;5;238;38;5;245m '"$ch"$' \e[0m ';;
      esac
      (( ${rank[${mark[i]}]:-0} > ${rank[${kb[${gss[i]}]:-}]:-0} )) && kb[${gss[i]}]=${mark[i]}  # keyboard: keep best
    done
    (( n++ )); printf '  %s\n\n' "$row"
    _ccplay_wordle_kb
    if [[ "$guess" == "$word" ]]; then
      local plural=tries; (( n == 1 )) && plural=try
      printf '  \e[1;32m🎉 solved in %d %s!\e[0m\n' "$n" "$plural"; return 0
    fi
  done
  printf '  \e[31mout of tries — it was \e[1m%s\e[0m\e[0m\n' "$word"
}
ccplay() {   # mini games to pass the time while Claude thinks (no session impact)
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccplay; return 0; }
  local -a games=(wordle guess rps flip roll react math hangman scramble 8ball)
  typeset -A _cc_g_desc _cc_g_instr
  _cc_g_desc=(
    wordle   "Wordle — guess a 5-letter word in 6 tries (colored tiles)"
    guess    "Hi-Lo — guess a hidden number 1–100"
    rps      "Rock–paper–scissors vs the computer"
    flip     "Flip a coin"
    roll     "Roll two dice"
    react    "Reaction timer — how fast can you hit a key?"
    math     "Quick arithmetic quiz (5 questions)"
    hangman  "Guess the word letter by letter"
    scramble "Unscramble the jumbled word"
    8ball    "Magic 8-ball — ask a yes/no question"
  )
  _cc_g_instr=(
    wordle   "Guess a real 5-letter word in 6 tries. Tiles: green=right spot · yellow=in word, wrong spot · gray=absent. Used letters dim on the keyboard below. q quits."
    guess    "I picked a number 1–100. Type a guess and Enter; I'll say ↑ higher / ↓ lower. q quits."
    rps      "Type r, p, or s and Enter. I pick secretly, then we compare."
    flip     "Just watch — heads or tails."
    roll     "Just watch — two six-sided dice."
    react    "Press any key to start. When you see GO!, hit any key as fast as you can."
    math     "5 questions; type each answer and Enter. I'll score you."
    hangman  "Guess one letter at a time. 7 misses allowed; q quits."
    scramble "I show a jumbled word — type the unscrambled word and Enter."
    8ball    "Type a yes/no question and Enter; the 8-ball answers."
  )
  local g="${1-}"
  if [[ -z $g ]]; then
    printf '\e[1m🎮 Pick a game\e[0m\n'
    local i
    for (( i=1; i<=${#games}; i++ )); do
      printf '  \e[36m%d\e[0m) \e[1m%-9s\e[0m \e[2m%s\e[0m\n' "$i" "${games[i]}" "${_cc_g_desc[${games[i]}]}"
    done
    local choice; read "choice?  choose 1–${#games} (or name, Enter to cancel): " || return 0
    [[ -z $choice ]] && return 0
    if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#games} )); then g=${games[choice]}
    else g=${choice:l}; fi
  fi
  case $g in
    list|-h|--help|help) printf 'games: %s\n' "${games[*]}"; return 0;;
  esac
  if [[ -z ${_cc_g_desc[$g]-} ]]; then printf "unknown game '%s' — try: %s\n" "$g" "${games[*]}"; return 2; fi
  printf '\e[2m— %s\e[0m\n' "${_cc_g_instr[$g]}"      # instructions before every game
  _ccplay_$g
}

ccname() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccname; return 0; }
  local id="${CLAUDE_CODE_SESSION_ID-}"
  [[ -z "$id" ]] && { echo "not inside a Claude session (CLAUDE_CODE_SESSION_ID unset)"; return 1; }
  local n i
  while IFS=$'\t' read -r n i; do [[ "$i" == "$id" ]] && { print -r -- "$n"; return 0; }; done < <(_cc_rows)
  echo "this session ($id) is not in the map — add it with: ccadd \"<name>\"  (or /ccadd)"
  return 1
}

# Interactive name chooser for name-taking commands invoked with no argument.
# Sets _CC_SEL_NAME. rc: 0 chosen · 1 cancelled/none · 2 not a TTY (caller prints usage).
_cc_pick_name() {
  [[ -t 0 && -t 1 ]] || return 2
  _CC_PICKED_ID=; _CC_PICKED_NAME=
  _cc_pick || return 1
  _CC_SEL_NAME=$_CC_PICKED_NAME
}

# Multi-select picker over mapped names (type-to-filter, Space ticks, Enter confirms).
# On success sets the global array _CC_SEL_NAMES to the chosen names (map order) and returns 0.
# Returns 2 if not a TTY, 1 if cancelled / nothing chosen.
_cc_pick_names() {
  [[ -t 0 && -t 1 ]] || return 2
  set -A _CC_SEL_NAMES
  local -a names ids
  local name id
  while IFS=$'\t' read -r name id; do names+=("$name"); ids+=("$id"); done < <(_cc_rows)
  (( ${#names} == 0 )) && { print -u2 "No conversations in the map ($_CC_MAP)."; return 1; }
  local n=${#names}
  local -a checked; local i; for (( i=1; i<=n; i++ )); do checked[i]=0; done
  local filter="" key seq sel=1 drawn=0 cancelled=
  local -a fidx
  local _recompute _draw
  _recompute() {
    fidx=(); local i lf="${filter:l}"
    for (( i=1; i<=n; i++ )); do
      [[ -z $lf || "${names[i]:l}" == *"$lf"* ]] && fidx+=($i)
    done
    (( sel < 1 )) && sel=1
    if (( ${#fidx} == 0 )); then sel=0; elif (( sel > ${#fidx} )); then sel=${#fidx}; fi
  }
  _draw() {
    (( drawn > 0 )) && printf '\e[%dA\r\e[J' "$drawn" >&2
    printf '\e[1mFetch\e[0m \e[2mfilter:\e[0m %s\e[7m \e[0m \e[2m(type · ↑/↓ · Space tick · Enter · Esc)\e[0m\n' "$filter" >&2
    local shown=1 j real box
    if (( ${#fidx} == 0 )); then
      printf '  \e[2m(no matches)\e[0m\n' >&2; (( shown++ ))
    else
      for (( j=1; j<=${#fidx}; j++ )); do
        real=${fidx[j]}
        [[ ${checked[real]} == 1 ]] && box='[x]' || box='[ ]'
        if (( j==sel )); then printf '  \e[7m%s %s\e[0m\n' "$box" "${names[real]}" >&2
        else printf '  %s \e[36m%s\e[0m\n' "$box" "${names[real]}" >&2; fi
        (( shown++ ))
      done
    fi
    drawn=$shown
  }
  tput civis 2>/dev/null
  _recompute; _draw
  while true; do
    read -rsk1 key
    case $key in
      $'\e') seq=''; read -rsk2 -t 0.4 seq 2>/dev/null
        case $seq in
          '[A'|'OA') (( sel>1 )) && (( sel-- ));;
          '[B'|'OB') (( sel<${#fidx} )) && (( sel++ ));;
          '') if [[ -n $filter ]]; then filter=""; sel=1; _recompute; else cancelled=1; break; fi;;
        esac;;
      ' ') (( ${#fidx}>=1 )) && { local r=${fidx[sel]}; checked[r]=$(( 1 - checked[r] )); };;
      $'\n'|$'\r') break;;
      $'\x7f'|$'\b') filter="${filter%?}"; sel=1; _recompute;;
      *) [[ $key == [[:print:]] && $key != ' ' ]] && { filter+="$key"; sel=1; _recompute; };;
    esac
    _draw
  done
  tput cnorm 2>/dev/null
  [[ -n $cancelled ]] && { print -u2 "cancelled"; return 1; }
  # collect ticked names; if none ticked, fall back to the highlighted row
  for (( i=1; i<=n; i++ )); do [[ ${checked[i]} == 1 ]] && _CC_SEL_NAMES+=("${names[i]}"); done
  if (( ${#_CC_SEL_NAMES} == 0 )); then
    (( sel >= 1 && ${#fidx} >= 1 )) && _CC_SEL_NAMES+=("${names[${fidx[sel]}]}")
  fi
  (( ${#_CC_SEL_NAMES} == 0 )) && return 1
  return 0
}

ccresume() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccresume; return 0; }
  local q="${1-}" name id match_id match_name
  [ -z "$q" ] && { cclist; return; }                      # no arg -> open picker
  while IFS=$'\t' read -r name id; do
    [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }
  done < <(_cc_rows)
  if [[ -z $match_id ]]; then                             # fall back to substring match
    while IFS=$'\t' read -r name id; do
      [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }
    done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  echo "Resuming '$match_name' -> $match_id"
  _cc_launch "$match_id"
}

ccbranch() {   # fork a conversation's full history into a NEW session (original untouched)
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccbranch; return 0; }
  local q name id match_id match_name
  if [[ -n "${1-}" ]]; then q="$1"
  else _cc_pick_name; case $? in 2) echo 'usage: ccbranch "<name>"'; return 2;; 1) return 1;; esac; q=$_CC_SEL_NAME; fi
  while IFS=$'\t' read -r name id; do
    [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }
  done < <(_cc_rows)
  if [[ -z $match_id ]]; then
    while IFS=$'\t' read -r name id; do
      [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }
    done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  echo "Branching '$match_name' → new session forked from $match_id (original untouched)"
  _cc_launch "$match_id" --fork-session
}

ccfind() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccfind; return 0; }
  local q="${1-}"
  [ -z "$q" ] && { echo 'usage: ccfind "<text>"'; return 2; }
  local hits
  hits=$(awk -v q="${q:l}" -F'|' '
    /^\|/ && /`/ {
      if (index(tolower($0), q) == 0) next;
      name=$2; id=$3; notes="";
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",name);
      gsub(/[`[:space:]]/,"",id);
      for (i=4;i<=NF;i++) notes=notes (i>4?"|":"") $i;
      sub(/\|[[:space:]]*$/,"",notes); gsub(/^[[:space:]]+|[[:space:]]+$/,"",notes);
      printf "  \033[36m%s\033[0m  \033[2m%s\033[0m\n    %s\n", name, id, notes;
    }' "$_CC_MAP")
  [[ -z $hits ]] && { echo "No entry matching '$q'."; return 1; }
  print -r -- "$hits"
}

ccmonitor() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccmonitor; return 0; }
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local name id f mt now age age_s tok sstatus stag dot disp limit count=0
  limit="${1:-0}"   # 0 = all mapped
  now=$(date +%s)
  local total_tok=0 nwork=0 nwait=0 ninact=0
  printf '  \e[1m%s  %s  %s   %s\e[0m\n' "${(r:28:):-CONVERSATION}" "${(l:8:):-OUT}" "${(l:6:):-AGE}" "STATUS"
  printf '  \e[2m%s\e[0m\n' "${(r:54::─:):-}"
  while IFS=$'\t' read -r name id; do
    disp="$name"; (( ${#disp} > 28 )) && disp="${disp[1,27]}…"
    local -a tf; tf=( "$base"/projects/*/"$id.jsonl"(N) )
    if (( ${#tf} == 0 )); then
      printf '  \e[2m%s  %s  %s   ○ %s\e[0m\n' "${(r:28:):-$disp}" "${(l:8:):--}" "${(l:6:):--}" "no transcript"
    else
      f=${tf[1]}
      local raw=$(grep -oE '"output_tokens":[0-9]+' "$f" 2>/dev/null | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
      total_tok=$(( total_tok + raw ))
      tok=$(awk -v s="$raw" 'BEGIN{if(s>=1000000)printf "%.1fM",s/1000000;else if(s>=1000)printf "%.0fK",s/1000;else if(s>0)print s;else print "-"}')
      mt=$(_cc_mtime "$f")
      age_s=$(( now - ${mt:-now} ))
      if   (( age_s < 60 ));    then age="${age_s}s"
      elif (( age_s < 3600 ));  then age="$(( age_s / 60 ))m"
      elif (( age_s < 86400 )); then age="$(( age_s / 3600 ))h"
      else age="$(( age_s / 86400 ))d"; fi
      if   (( age_s < 30 ));  then sstatus="working";  stag=$'\e[1;32m'; dot="●"; (( nwork++ ))
      elif (( age_s < 300 )); then sstatus="waiting";  stag=$'\e[1;33m'; dot="●"; (( nwait++ ))
      else sstatus="inactive"; stag=$'\e[2m';          dot="○"; (( ninact++ )); fi
      printf '  %s  %s  %s   %s%s %s\e[0m\n' "${(r:28:):-$disp}" "${(l:8:):-$tok}" "${(l:6:):-$age}" "$stag" "$dot" "$sstatus"
    fi
    (( limit > 0 && ++count >= limit )) && break
  done < <(_cc_rows)
  local total_disp=$(awk -v s="$total_tok" 'BEGIN{if(s>=1000000)printf "%.1fM",s/1000000;else if(s>=1000)printf "%.0fK",s/1000;else print s}')
  printf '  \e[2m%s\e[0m\n' "${(r:54::─:):-}"
  printf '  \e[2m%d chats · %s output tokens · \e[1;32m●\e[0;2m working <30s   \e[1;33m●\e[0;2m waiting <5m   \e[2m○\e[0;2m inactive\e[0m\n' \
    "$(( nwork + nwait + ninact ))" "$total_disp"
}

_cc_all_resolve() {   # returns 0 iff EVERY arg matches a mapped name (exact or substring)
  local a hit name id
  for a in "$@"; do
    hit=
    while IFS=$'\t' read -r name id; do
      [[ "${name:l}" == "${a:l}" || "${name:l}" == *"${a:l}"* ]] && { hit=1; break; }
    done < <(_cc_rows)
    [[ -z $hit ]] && return 1
  done
  return 0
}

_cc_fetch_many() {   # $1 = refresh flag ("1" = regenerate all); rest = names
  setopt local_options no_monitor   # background jobs must not print "[5] 46843" notifications
  local refresh="${1-}"; shift
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; local cdir="$base/claudius-cache"
  local qq name id match_id match_name
  local -a ids names tfs cfiles gen
  # resolve every name up front (bail if any is unknown / has no transcript)
  for qq in "$@"; do
    match_id=; match_name=
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${qq:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
    if [[ -z $match_id ]]; then
      while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${qq:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
    fi
    [[ -z $match_id ]] && { echo "No session matching '$qq'. Known:"; _cc_plain; return 1; }
    local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
    (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)."; return 1; }
    ids+=("$match_id"); names+=("$match_name"); tfs+=("${tf[1]}"); cfiles+=("$cdir/$match_id.fetch.md")
  done
  mkdir -p "$cdir"
  # decide per chat which to (re)generate — announce each; prompt only for cached ones on a TTY
  local i ans age
  for i in {1..${#ids}}; do
    if [[ "$refresh" == 1 && -s "${cfiles[i]}" ]]; then
      gen+=($i); [[ -t 0 ]] && print -u2 -- "‘${names[i]}’ — cached, regenerating (-r)."
    elif [[ ! -s "${cfiles[i]}" ]]; then
      gen+=($i); [[ -t 0 ]] && print -u2 -- "‘${names[i]}’ — not summarised yet, will generate."
    elif [[ -t 0 ]]; then
      age=$(_cc_mtime_fmt "${cfiles[i]}")
      print -u2 -n "‘${names[i]}’ — cached $age.  [u]se / [r]egenerate? "
      read -k 1 ans; print -u2 ""
      [[ "${ans:l}" == r ]] && gen+=($i)
    fi   # non-TTY + cached → silently reuse
  done
  # (re)generate the chosen summaries in parallel background jobs
  if (( ${#gen} )); then
    print -u2 "Generating ${#gen} summary(ies) in parallel…"
    local idx
    for idx in $gen; do
      ( claude -p --no-session-persistence "Read the Claude Code session transcript (JSONL) at ${tfs[idx]} and produce a concise handoff summary of that conversation: goal, key decisions/answers, current state, open next steps, and important file/CR/ticket references. Use short bullet points." > "${cfiles[idx]}.tmp" 2>/dev/null && mv -f "${cfiles[idx]}.tmp" "${cfiles[idx]}" || rm -f "${cfiles[idx]}.tmp" ) &
    done
    wait
  fi
  # combine (in the order given) and print to stdout
  local combined=""
  for i in {1..${#ids}}; do
    if [[ -s "${cfiles[i]}" ]]; then
      combined+=$'\n\n# '"${names[i]}"$'\n\n'"$(cat -- "${cfiles[i]}")"
    else
      print -u2 -- $'\e[2m(no summary available for '"${names[i]}"$')\e[0m'
    fi
  done
  [[ -z "$combined" ]] && { echo "nothing to show."; return 1; }
  print -r -- "${combined# }"
  # terminal mode: offer to open a NEW Claude session seeded with the combined context
  [[ -t 0 ]] || return 0
  local yn
  print -u2 ""
  print -u2 -n "Start a NEW Claude session seeded with this context? [y/N] "
  read -k 1 yn; print -u2 ""
  if [[ "${yn:l}" == y ]]; then
    print -u2 "Starting a new session with context from ${#ids} chat(s)…"
    claude "I'm starting a new working session. Below are handoff summaries of prior Claude Code conversations I want to carry context from. Read them, then wait for my next instruction.${combined}"
  fi
}

_cc_gather_summaries() {   # $1=refresh flag; rest=names. Non-interactive: reuse cache, gen missing in parallel.
  setopt local_options no_monitor            # sets _CC_ASK_CONTEXT (combined) + _CC_ASK_NAMES; rc 0/1
  local refresh="${1-}"; shift
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; local cdir="$base/claudius-cache"
  local qq name id match_id match_name
  local -a ids names tfs cfiles gen
  for qq in "$@"; do
    match_id=; match_name=
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${qq:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
    if [[ -z $match_id ]]; then
      while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${qq:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
    fi
    [[ -z $match_id ]] && { echo "No session matching '$qq'. Known:" >&2; _cc_plain >&2; return 1; }
    local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
    (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)." >&2; return 1; }
    ids+=("$match_id"); names+=("$match_name"); tfs+=("${tf[1]}"); cfiles+=("$cdir/$match_id.fetch.md")
  done
  mkdir -p "$cdir"
  local i
  for i in {1..${#ids}}; do [[ "$refresh" == 1 || ! -s "${cfiles[i]}" ]] && gen+=($i); done
  if (( ${#gen} )); then
    print -u2 "Summarising ${#gen} chat(s)…"
    local idx
    for idx in $gen; do
      ( claude -p --no-session-persistence "Read the Claude Code session transcript (JSONL) at ${tfs[idx]} and produce a concise handoff summary: goal, key decisions/answers, current state, open next steps, important file/CR/ticket references. Short bullet points." > "${cfiles[idx]}.tmp" 2>/dev/null && mv -f "${cfiles[idx]}.tmp" "${cfiles[idx]}" || rm -f "${cfiles[idx]}.tmp" ) &
    done
    wait
  fi
  local combined=""; _CC_ASK_NAMES=()
  for i in {1..${#ids}}; do
    [[ -s "${cfiles[i]}" ]] && { combined+=$'\n\n# '"${names[i]}"$'\n\n'"$(cat -- "${cfiles[i]}")"; _CC_ASK_NAMES+=("${names[i]}"); }
  done
  [[ -z "$combined" ]] && { echo "no summaries available." >&2; return 1; }
  _CC_ASK_CONTEXT="${combined# }"; return 0
}

_cc_resolve_many() {   # names -> sets arrays _CC_RM_IDS/_CC_RM_NAMES/_CC_RM_TFS; rc 0 all-resolved, 1 else
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" qq name id match_id match_name
  set -A _CC_RM_IDS; set -A _CC_RM_NAMES; set -A _CC_RM_TFS
  for qq in "$@"; do
    match_id=; match_name=
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${qq:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
    if [[ -z $match_id ]]; then
      while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${qq:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
    fi
    [[ -z $match_id ]] && { echo "No session matching '$qq'. Known:" >&2; _cc_plain >&2; return 1; }
    local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
    (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)." >&2; return 1; }
    _CC_RM_IDS+=("$match_id"); _CC_RM_NAMES+=("$match_name"); _CC_RM_TFS+=("${tf[1]}")
  done
  return 0
}

_cc_transcript_text() {   # $1=id $2=jsonl -> ensures a compact text extract exists (cached, fresh); prints its path
  local id="$1" jsonl="$2" base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" cdir; cdir="$base/claudius-cache"
  local out="$cdir/$id.text.md"
  mkdir -p "$cdir"
  if [[ ! -s "$out" || "$jsonl" -nt "$out" ]] || ! head -1 "$out" 2>/dev/null | grep -q 'claudius-extract v3'; then
    command -v python3 >/dev/null 2>&1 || { print -r -- "$jsonl"; return; }   # no python -> fall back to raw file
    python3 - "$jsonl" "$out" <<'PY' 2>/dev/null || { print -r -- "$jsonl"; return; }
import sys, json
src, dst = sys.argv[1], sys.argv[2]
# v3: keep the CONTEXT that v2 dropped — tool-call INPUTS (the command/query/path you actually ran),
# tool-result head AND tail (not a blind head cut), and a short slice of thinking. This is what makes
# ccask able to answer "what was the redrive command / which file / which query" instead of just "[tool: Bash]".
RES_HEAD, RES_TAIL, THINK_CAP = 1400, 500, 600   # per-block caps; generous but bounded
# fields worth surfacing from a tool_use input, in rough priority order
INPUT_KEYS = ("command", "cmd", "query", "q", "pattern", "path", "file_path", "filePath",
              "url", "prompt", "description", "old_string", "content", "notebook_path")
def clip(s, n):
    s = str(s).strip()
    return s if len(s) <= n else s[:n] + "…"
def summarize_input(inp):
    if not isinstance(inp, dict): return clip(inp, 200)
    picks = []
    for k in INPUT_KEYS:
        v = inp.get(k)
        if v not in (None, ""):
            picks.append(f"{k}={clip(v, 200)}")
        if len(picks) >= 3: break
    return " ".join(picks) or clip(json.dumps(inp, ensure_ascii=False), 200)
def render(c):
    if isinstance(c, str): return c
    if not isinstance(c, list): return ""
    parts = []
    for b in c:
        if not isinstance(b, dict): continue
        t = b.get("type")
        if t == "text": parts.append(b.get("text", ""))
        elif t == "thinking":
            th = str(b.get("thinking", "")).strip()
            if th: parts.append(f"[thinking: {clip(th, THINK_CAP)}]")
        elif t == "tool_use":
            inp = summarize_input(b.get("input", {}))
            parts.append(f"[tool: {b.get('name','?')}{(' ' + inp) if inp else ''}]")
        elif t == "tool_result":
            r = b.get("content", "")
            if isinstance(r, list): r = " ".join(x.get("text","") for x in r if isinstance(x, dict))
            r = str(r).strip()
            if r:
                if len(r) > RES_HEAD + RES_TAIL + 20:
                    r = r[:RES_HEAD] + " …[trimmed]… " + r[-RES_TAIL:]   # keep head AND tail
                parts.append(f"[tool result: {r}]")
    return "\n".join(p for p in parts if p)
with open(src) as f, open(dst, "w") as w:
    w.write("<!-- claudius-extract v3 -->\n")
    for line in f:
        try: o = json.loads(line)
        except Exception: continue
        m = o.get("message")
        if not isinstance(m, dict): continue
        role = m.get("role")
        if role not in ("user", "assistant"): continue
        txt = render(m.get("content")).strip()
        if txt: w.write(f"\n## {role.upper()}\n{txt}\n")
PY
  fi
  print -r -- "$out"
}

_cc_ask_excerpts() {   # $1=question $2=budgetChars ; rest = "name<TAB>file" -> prints the most relevant turns
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$@" <<'PY' 2>/dev/null
import sys, re
from collections import OrderedDict
q = sys.argv[1]; budget = int(sys.argv[2]); pairs = sys.argv[3:]
STOP = set("the a an of in to for and or how does do is are was were be it its this that these those with on at by from as what which when where why who whom about into your my our their has have can could would should will".split())
terms = [w for w in re.findall(r"[a-z0-9_]+", q.lower()) if len(w) >= 3 and w not in STOP]
terms = list(dict.fromkeys(terms)) or [w for w in re.findall(r"[a-z0-9_]+", q.lower()) if len(w) >= 2]
# collect relevant blocks per chat, preserving the chat order the caller passed (= relevance rank)
by_chat = OrderedDict(); order = 0
for pair in pairs:
    if "\t" not in pair: continue
    name, path = pair.split("\t", 1)
    by_chat.setdefault(name, [])
    try: data = open(path, encoding="utf-8", errors="ignore").read()
    except Exception: continue
    parts = re.split(r"(?m)^(## (?:USER|ASSISTANT))\s*$", data)
    i = 1
    while i < len(parts):
        text = (parts[i] + "\n" + (parts[i+1] if i+1 < len(parts) else "")).strip()
        i += 2; order += 1
        low = text.lower()
        distinct = sum(1 for t in terms if t in low)
        if distinct:
            by_chat[name].append((distinct, sum(low.count(t) for t in terms), order, text))
for name in by_chat: by_chat[name].sort(key=lambda b: (b[0], b[1]), reverse=True)
# round-robin across chats (best block of chat1, chat2, …, then 2nd-best of each) so every relevant
# chat is represented and no single noisy chat monopolizes the budget
names = list(by_chat.keys())
rr = []
for r in range(max((len(v) for v in by_chat.values()), default=0)):
    for name in names:
        if r < len(by_chat[name]):
            b = by_chat[name][r]; rr.append((name, b[2], b[3]))
sel = []; used = 0
for name, ordr, text in rr:
    if used + len(text) > budget and sel: continue
    sel.append((name, ordr, text)); used += len(text)
    if used >= budget: break
# output grouped by chat (rank order), blocks in original chronological order
grouped = OrderedDict((n, []) for n in names)
for name, ordr, text in sel: grouped[name].append((ordr, text))
out = []
for name in names:
    items = sorted(grouped[name])
    if not items: continue
    out.append(f"\n### From chat: {name}\n"); out.extend(t for _, t in items)
print("\n\n".join(out))
PY
}

_cc_claude_spin() {   # run claude -p --no-session-persistence "$1" with a live spinner on stderr; echo the answer to stdout
  local prompt="$1" tmp; tmp=$(mktemp -t ccask 2>/dev/null || printf '/tmp/ccask.%d.md' $$)
  claude -p --no-session-persistence "$prompt" > "$tmp" 2>/dev/null &
  local pid=$! t0=$SECONDS i=0 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  trap 'kill $pid 2>/dev/null' INT
  if [[ -t 2 ]]; then
    while kill -0 $pid 2>/dev/null; do
      printf '\r\e[2m  %s thinking… %ds  (Ctrl-C to cancel)\e[0m' "${spin[i % ${#spin} + 1]}" "$(( SECONDS - t0 ))" >&2
      sleep 0.2; (( i++ ))
    done
    printf '\r\e[2K' >&2
  fi
  wait $pid 2>/dev/null
  trap - INT
  local out; out=$(< "$tmp"); rm -f "$tmp"
  print -r -- "$out"
}

_cc_clipcmd() {   # echo a clipboard command if one exists on this system, else fail
  if   command -v pbcopy  >/dev/null 2>&1; then print -r -- 'pbcopy'
  elif command -v wl-copy >/dev/null 2>&1; then print -r -- 'wl-copy'
  elif command -v xclip   >/dev/null 2>&1; then print -r -- 'xclip -selection clipboard'
  elif command -v xsel    >/dev/null 2>&1; then print -r -- 'xsel -b'
  else return 1; fi
}
_cc_md_ansi() {   # lightweight markdown -> ANSI renderer (headers, bold, code, bullets)
  print -r -- "$1" | perl -0777 -pe '
    s{```[a-zA-Z0-9_-]*\n(.*?)\n?```}{ my $c=$1; $c=~s/^/    /mg; "\e[38;5;79m$c\e[0m" }ges;
    s/^(#{1,2})\s+(.*)$/\e[1;36m$2\e[0m/mg;
    s/^#{3,6}\s+(.*)$/\e[1m$1\e[0m/mg;
    s/\*\*(.+?)\*\*/\e[1m$1\e[0m/g;
    s/(?<!`)`([^`\n]+)`(?!`)/\e[38;5;214m$1\e[0m/g;
    s/^(\s*)[-*+]\s+/${1}\e[36m•\e[0m /mg;
  '
}
_cc_present() {   # show a markdown answer with styling on a TTY, then offer to copy the raw markdown
  local md="$1"
  [[ -t 1 ]] || { print -r -- "$md"; return; }          # piped/redirected -> raw markdown (unchanged)
  if command -v glow >/dev/null 2>&1; then print -r -- "$md" | glow -; else _cc_md_ansi "$md"; fi
  [[ -t 0 ]] || return
  local clip; clip=$(_cc_clipcmd) || return
  local yn; print -u2 -n $'\e[2mCopy raw markdown to clipboard? [y/N] \e[0m'; read -k 1 yn; print -u2 ""
  [[ "${yn:l}" == y ]] && { print -r -- "$md" | eval "$clip" 2>/dev/null && print -u2 -- $'\e[2m✓ copied as markdown\e[0m' || print -u2 -- $'\e[2m(copy failed)\e[0m'; }
}

_cc_label_for() {   # $1=id $2=jsonl -> display label: mapped name, else first message (short), else short id
  local id="$1" f="$2" n i prev
  while IFS=$'\t' read -r n i; do [[ "$i" == "$id" ]] && { print -r -- "$n"; return; }; done < <(_cc_rows)
  prev=$(grep -m1 '"type":"user"' "$f" 2>/dev/null | grep -oE '"content":"[^"]*"' | head -1 | sed 's/"content":"//; s/"$//')
  [[ -n $prev ]] && { print -r -- "${prev:0:40}"; return; }
  print -r -- "${id:0:8}…"
}

_cc_ask_all() {   # cross-chat ask: rank ALL sessions by relevance, answer from the top few, cite them
  local q="$1" base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  # query terms: lowercase, keep alphanumeric words >=3 chars that aren't stopwords
  local -A stop; local w
  for w in the a an of and or is are was were be to in on at by for from as it its this that with what which when where why who how do does did can could would should will your my our their has have not; do stop[$w]=1; done
  local -a qwords qt
  local ql=${(L)q}                              # NOTE: lowercase in a temp var first — the nested
  qwords=(${(s: :)${ql//[^a-z0-9 ]/ }})         # form ${(s::)${(L)q//…}} silently drops some words in zsh
  for w in $qwords; do [[ ${#w} -ge 3 && -z ${stop[$w]-} ]] && qt+=("$w"); done
  (( ${#qt} == 0 )) && qt=($qwords)
  (( ${#qt} == 0 )) && { echo "ask a real question, e.g. ccask -a \"what did we decide about X\""; return 2; }
  local pat=${(j:|:)qt}
  local -a allfiles; allfiles=( "$base"/projects/*/*.jsonl(N) )
  (( ${#allfiles} == 0 )) && { echo "no sessions found on disk."; return 1; }
  # Build the corpus, skipping Claudius' own headless runs AND its "new session seeded with summaries"
  # boilerplate; while here, capture how many query terms hit each chat's FIRST message (its topic).
  local -a files; local ff0 fum fl t2; typeset -A fmsg
  for ff0 in $allfiles; do
    _cc_is_ephemeral "$ff0" && continue   # skip Claudius' own one-shots / seeded sessions (see helper)
    fum=$(grep -m1 '"type":"user"' "$ff0" 2>/dev/null)
    files+=("$ff0"); fl=${fum:l}; local c=0
    for t2 in $qt; do [[ "$fl" == *"$t2"* ]] && (( c++ )); done
    fmsg[$ff0]=$c
  done
  (( ${#files} == 0 )) && { echo "no sessions found on disk."; return 1; }
  print -u2 -- $'\e[2mSearching '"${#files}"$' chats for: '"${(j:, :)qt}"$'…\e[0m'
  # Body relevance by IDF-weighted term coverage: a term in FEW chats (e.g. "slack") is far more
  # discriminative than one in almost every chat (e.g. "there"/"update"). One `grep -l` per term over
  # all files gives both the document-frequency (df) AND which files hit.
  local N=${#files} t= df= w= ff= total=; local -a mf; typeset -A score   # explicit = : a bare re-decl of an already-set var (w/t from earlier loops) prints it in zsh
  for t in $qt; do
    mf=(${(f)"$(LC_ALL=C grep -liF -- "$t" $files 2>/dev/null)"})
    df=${#mf}; (( df == 0 )) && continue
    w=$(( N - df + 1 ))
    for ff in $mf; do score[$ff]=$(( ${score[$ff]:-0} + w )); done
  done
  # Final score (Generative Agents-style): relevance is the dominant signal; RECENCY and IMPORTANCE
  # are bounded tie-breakers, applied multiplicatively so a clearly-more-relevant chat always still
  # wins, and they only reorder comparably-relevant chats. recency = smooth decay by age (half-ish
  # life CCASK_RECENCY_DAYS); importance = you cared enough to NAME the chat (it's in the map).
  local wr=${CCASK_W_RECENCY:-0.3} wi=${CCASK_W_IMPORTANCE:-0.2} hl=${CCASK_RECENCY_DAYS:-30}
  zmodload zsh/datetime 2>/dev/null; zmodload zsh/stat 2>/dev/null
  local now=${EPOCHSECONDS:-0}
  typeset -A mapped; local -a rows; rows=(${(f)"$(_cc_rows 2>/dev/null)"}); local r rid
  for r in $rows; do rid=${${(s:	:)r}[2]}; [[ -n $rid ]] && mapped[$rid]=1; done
  local -a scored=(); local base id3 rec imp final; local -a st
  for ff in $files; do
    base=$(( ${fmsg[$ff]:-0} * 1000 + ${score[$ff]:-0} ))
    (( base > 0 )) || continue
    rec=0                                             # recency in (0,1]; 0 if mtime unavailable
    if st=(); zstat -A st +mtime "$ff" 2>/dev/null && (( now > 0 && st[1] > 0 )); then
      rec=$(( 1.0 / (1.0 + ((now - st[1]) / 86400.0) / hl) ))
    fi
    id3=${${ff:t}:r}; imp=0; [[ -n ${mapped[$id3]-} ]] && imp=1
    final=$(( base * (1.0 + wr*rec + wi*imp) ))
    scored+=("$(printf '%013.3f' $final)"$'\t'"$ff")   # zero-pad so lexical sort == numeric sort
  done
  (( ${#scored} == 0 )) && { echo "CANNOT ANSWER: none of your saved chats mention $(print -r -- "${(j:, :)qt}")."; return 1; }
  scored=("${(@f)$(printf '%s\n' "${scored[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr)}")
  local K=${CCASK_TOPK:-5}
  local -a top=(${scored[1,K]})
  local line= sc2= f2= id2= tf= lbl=; local -a pairs labels   # explicit = : bare re-decl of an already-set var prints it in zsh
  for line in "${top[@]}"; do
    f2=${line#*$'\t'}; id2=${${f2:t}:r}
    tf=$(_cc_transcript_text "$id2" "$f2")
    lbl=$(_cc_label_for "$id2" "$f2")
    pairs+=("$lbl"$'\t'"$tf"); labels+=("$lbl")
  done
  print -u2 -- $'\e[2mMost relevant: '"${(j:, :)labels}"$'\e[0m'
  local excerpts; excerpts=$(_cc_ask_excerpts "$q" 100000 "${pairs[@]}")
  [[ -z "$excerpts" ]] && { echo "CANNOT ANSWER: found mentions but couldn't extract usable context (is python3 available?)."; return 1; }
  if [[ -n ${2-} ]]; then                                 # --context: print material for the caller to answer from
    print -r -- "### Relevant excerpts from your chats (most relevant: ${(j:, :)labels})"
    print -r -- "$excerpts"; return 0
  fi
  local prompt out
  prompt="You are answering from excerpts of MULTIPLE past coding chats; each block is headed '### From chat: <name>'. Answer the question strictly from these excerpts, and CITE the chat name(s) each part of your answer comes from, e.g. (from “Backend Changes”). Quote exact formulas, numbers, and file/CR/ticket identifiers when present. If the excerpts do not contain the answer, reply with a single line beginning exactly 'CANNOT ANSWER:' and say what is missing. Never invent anything not in the excerpts."$'\n\n'"QUESTION: $q"$'\n\n'"=== EXCERPTS (from your most relevant chats) ==="$'\n'"$excerpts"
  out=$(_cc_claude_spin "$prompt")
  [[ -z "$out" ]] && { echo "no answer produced (cancelled, or the model returned nothing)."; return 1; }
  _cc_present "$out"
}

ccask() {   # ask Claude a one-shot question about one or more saved chats (headless; no new conversation)
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccask; return 0; }
  command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH."; return 1; }
  local refresh= summary= allmode= context=
  while [[ "${1-}" == -* ]]; do
    case "$1" in
      -r|--refresh) refresh=1; shift ;;
      -s|--summary) summary=1; shift ;;
      -a|--all)     allmode=1; shift ;;
      -x|--context) context=1; shift ;;   # print the retrieved excerpts instead of answering (used by /ccask)
      *) break ;;
    esac
  done
  local q="${1-}"
  [[ -z $q ]] && { echo 'usage: ccask [-a] [-s] [-r] [-x] "<question>" [<chat> ...]'; return 2; }
  shift
  [[ -n $allmode ]] && { _cc_ask_all "$q" "$context"; return; }   # -a: search across ALL chats, cite sources
  local -a chats=("$@")
  if (( ${#chats} == 0 )); then
    if [[ -t 0 && -t 1 ]]; then
      _cc_pick_names; case $? in 2) echo 'usage: ccask [-s] [-r] "<question>" [<chat> ...]'; return 2;; 1) return 1;; esac
      chats=("${_CC_SEL_NAMES[@]}")
    else
      echo 'ccask: name at least one chat — e.g. ccask "<question>" "Backend Changes"'; return 2
    fi
  fi
  local prompt out ctxmat=
  if [[ -n $summary ]]; then
    # fast/cheap mode: answer from the cached handoff summaries (lossy — misses fine detail)
    _CC_ASK_CONTEXT= _CC_ASK_NAMES=()
    _cc_gather_summaries "$refresh" "${chats[@]}" || return 1
    print -u2 -- $'\e[2mAsking (summaries): '"${(j:, :)_CC_ASK_NAMES}"$'…\e[0m'
    ctxmat=$_CC_ASK_CONTEXT
    prompt="Answer the question using ONLY the conversation summaries below. If they lack the detail to answer, reply with a single line beginning exactly 'CANNOT ANSWER:' and state what is missing (suggest dropping -s so I read the full transcripts, or -r to refresh). Never invent details."$'\n\n'"QUESTION: $q"$'\n\n'"=== CONVERSATION SUMMARIES ==="$'\n'"$_CC_ASK_CONTEXT"
  else
    # default: extract compact text, RETRIEVE the relevant turns locally (cheap grep/rank), then
    # send claude only that focused excerpt — so it answers in seconds, not by grepping a big file.
    _cc_resolve_many "${chats[@]}" || return 1
    print -u2 -- $'\e[2mPreparing '"${#_CC_RM_TFS}"$' transcript(s): '"${(j:, :)_CC_RM_NAMES}"$'…\e[0m'
    local i; local -a pairs textfiles tf
    for i in {1..${#_CC_RM_TFS}}; do
      tf=$(_cc_transcript_text "${_CC_RM_IDS[i]}" "${_CC_RM_TFS[i]}")
      textfiles+=("$tf"); pairs+=("${_CC_RM_NAMES[i]}"$'\t'"$tf")
    done
    local excerpts; excerpts=$(_cc_ask_excerpts "$q" 100000 "${pairs[@]}")
    if [[ -n "$excerpts" ]]; then
      ctxmat=$excerpts
      prompt="Answer the question strictly and specifically from the conversation excerpts below — the most relevant turns, pre-selected for you (## USER / ## ASSISTANT). Quote exact formulas, numbers, code line references, and file/CR/ticket identifiers when present. If the excerpts genuinely do not contain the answer, reply with a single line beginning exactly 'CANNOT ANSWER:' and state what is missing. Never invent anything not in the excerpts."$'\n\n'"QUESTION: $q"$'\n\n'"=== RELEVANT EXCERPTS ==="$'\n'"$excerpts"
    else
      # fallback (no python, or no keyword hit): let claude read the extract file(s) itself
      prompt="Read the following conversation transcript extract file(s) (## USER / ## ASSISTANT turns), search them, and answer strictly from their content — quote exact formulas/numbers/ids. If not present, reply beginning 'CANNOT ANSWER:'. Never invent."$'\n\n'"QUESTION: $q"$'\n\n'"TRANSCRIPTS:"$'\n'
      for i in {1..${#textfiles}}; do prompt+="- ${_CC_RM_NAMES[i]}: ${textfiles[i]}"$'\n'; done
    fi
  fi
  if [[ -n $context ]]; then                              # --context: print material, don't call the model
    [[ -z "$ctxmat" ]] && { echo "no excerpts retrieved."; return 1; }
    print -r -- "$ctxmat"; return 0
  fi
  out=$(_cc_claude_spin "$prompt")
  [[ -z "$out" ]] && { echo "no answer produced (cancelled, or the model returned nothing)."; return 1; }
  _cc_present "$out"
}

ccfetch() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccfetch; return 0; }
  # Usage:
  #   ccfetch "<name>" [extra]           summarise a mapped chat (cached; instant on repeat)
  #   ccfetch "<A>" "<B>" "<C>"          fetch MULTIPLE chats (per-chat use/regenerate, parallel)
  #   ccfetch -r "<name>"                refresh — regenerate the cached summary
  #   ccfetch --file path.md [extra]     summarise an ARBITRARY file (never cached)
  #   ccfetch @path.md [extra]           shorthand for --file
  command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH."; return 1; }
  local refresh= q src extra="" picked=
  [[ "${1-}" == "-r" || "${1-}" == "--refresh" ]] && { refresh=1; shift; }
  q="${1-}"
  # --file / @ : arbitrary file, no cache
  if [[ "$q" == "--file" || "$q" == "-f" || "$q" == @* ]]; then
    if [[ "$q" == @* ]]; then src="${q#@}"; shift; else src="${2-}"; shift 2 2>/dev/null; fi
    extra="$*"
    [ -z "$src" ] && { echo "usage: ccfetch --file <path.md> [extra]"; return 2; }
    [[ -r "$src" ]] || { echo "File not readable: $src"; return 1; }
    print -u2 "Summarising file $src…"
    claude -p --no-session-persistence "Read the document at $src and produce a concise summary in short bullet points: goal/context, key decisions, current state, open next steps, important references. ${extra}"
    return
  fi
  # name mode
  if [[ -z "$q" ]]; then
    # no name given → multi-select picker (Space ticks several; Enter on one = single)
    _cc_pick_names; case $? in 2) echo 'usage: ccfetch [-r] "<name>" [extra]  |  ccfetch --file <path.md>'; return 2;; 1) return 1;; esac
    if (( ${#_CC_SEL_NAMES} >= 2 )); then _cc_fetch_many "$refresh" "${_CC_SEL_NAMES[@]}"; return; fi
    q=${_CC_SEL_NAMES[1]}; picked=1
  fi
  # multi-name mode: 2+ args that ALL resolve to mapped names → parallel multi-fetch
  if [[ -z $picked && $# -ge 2 ]] && _cc_all_resolve "$@"; then
    _cc_fetch_many "$refresh" "$@"; return
  fi
  [[ -z $picked ]] && { shift; extra="$*"; }
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" name id match_id match_name
  while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  if [[ -z $match_id ]]; then
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
  (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)."; return 1; }
  local cdir="$base/claudius-cache"; local cfile="$cdir/$match_id.fetch.md"
  # serve from cache (only the default, no-extra summary is cached)
  if [[ -z $refresh && -z $extra && -s "$cfile" ]]; then
    print -u2 -- $'\e[2m(cached — ccfetch -r "'"$match_name"$'" to refresh)\e[0m'
    [[ "${tf[1]}" -nt "$cfile" ]] && print -u2 -- $'\e[2m(transcript changed since this summary; -r to refresh)\e[0m'
    cat -- "$cfile"; return 0
  fi
  print -u2 "Summarising '$match_name' ($match_id)…"
  local out
  out=$(claude -p --no-session-persistence "Read the Claude Code session transcript (JSONL) at ${tf[1]} and produce a concise handoff summary of that conversation: goal, key decisions/answers, current state, open next steps, and important file/CR/ticket references. Use short bullet points. ${extra}")
  [[ -z "$out" ]] && { echo "summary produced no output"; return 1; }
  [[ -z $extra ]] && { mkdir -p "$cdir"; print -r -- "$out" > "$cfile"; }   # cache the canonical summary
  print -r -- "$out"
}

cccache() {   # manage the ccfetch/ccspec summary cache
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help cccache; return 0; }
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" cdir
  cdir="$base/claudius-cache"
  case "${1-}" in
    ""|-l|--list)
      local -a files; files=( "$cdir"/*.fetch.md(N) "$cdir"/*.spec.md(N) )
      (( ${#files} == 0 )) && { echo "cache is empty ($cdir)"; return 0; }
      printf '\e[1m%-30s %-7s %s\e[0m\n' "CACHED CHAT" "TYPE" "GENERATED"
      local f id kind nm
      for f in $files; do
        id=${${${f:t}:r}:r}       # abc.fetch.md -> abc
        kind=${${f:t}:r:e}        # abc.fetch.md -> fetch
        nm=$(_cc_rows | awk -F'\t' -v i="$id" '$2==i{print $1}')
        printf '  %-30s %-7s %s\n' "${nm:-${id:0:8}…}" "$kind" "$(_cc_mtime_fmt "$f")"
      done
      ;;
    --clear|-c)
      if [[ -n "${2-}" ]]; then
        local name id target=
        while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${2:l}"* ]] && { target=$id; break; }; done < <(_cc_rows)
        [[ -z $target ]] && { echo "No mapped chat matching '$2'."; return 1; }
        rm -f "$cdir/$target.fetch.md" "$cdir/$target.spec.md" "$cdir/$target.text.md" && echo "cleared cache for '$2'."
      else
        rm -f "$cdir"/*.fetch.md(N) "$cdir"/*.spec.md(N) "$cdir"/*.text.md(N) 2>/dev/null; echo "cache cleared."
      fi
      ;;
    *) echo "usage: cccache [--list] | cccache --clear [name]"; return 2;;
  esac
}

cccleanup() {   # remove Claudius' own headless `claude -p` runs that got recorded as chats
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help cccleanup; return 0; }
  local yes=; [[ "${1-}" == -y || "${1-}" == --yes ]] && yes=1
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local -a hits; local f
  for f in "$base"/projects/*/*.jsonl(N); do _cc_is_internal "$f" && hits+=("$f"); done
  (( ${#hits} == 0 )) && { echo "No Claudius-internal sessions found — nothing to clean."; return 0; }
  print -u2 -- "Found ${#hits} Claudius-internal (headless claude -p) session(s) recorded as chats."
  if [[ -z $yes ]]; then
    print -u2 -n "Delete these transcript files? [y/N] "; local a; read -r a
    [[ "$a" == [yY]* ]] || { echo "aborted."; return 1; }
  fi
  local h n=0
  for h in $hits; do rm -f -- "$h" && (( n++ )); done
  echo "Removed $n session file(s). (Future asks won't be recorded — Claudius uses --no-session-persistence.)"
}

ccspec() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccspec; return 0; }
  local refresh= q out
  [[ "${1-}" == "-r" || "${1-}" == "--refresh" ]] && { refresh=1; shift; }
  if [[ -n "${1-}" ]]; then q="$1"; out="${2-}"
  else _cc_pick_name; case $? in 2) echo 'usage: ccspec [-r] "<name>" [output.md]'; return 2;; 1) return 1;; esac; q=$_CC_SEL_NAME; out=""; fi
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local name id match_id match_name
  while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  if [[ -z $match_id ]]; then
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
  (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)."; return 1; }
  if [[ -z "$out" ]]; then
    local slug; slug=$(print -r -- "${match_name:l}" | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')
    out="./${slug}.spec.md"
  fi
  local cdir="$base/claudius-cache"; local cfile="$cdir/$match_id.spec.md"
  # (re)generate into cache unless a fresh cached spec exists
  if [[ -n $refresh || ! -s "$cfile" ]]; then
    command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH."; return 1; }
    print -u2 "Generating spec for '$match_name' ($match_id)…"
    local gen
    gen=$(claude -p --no-session-persistence "Read the Claude Code session transcript (JSONL) at ${tf[1]} and write a SPEC document in Markdown for this work. Sections: '# <Title>', '## Goal / Context', '## Key Decisions', '## Tasks' (as - [ ] / - [x] checkbox items covering the work involved, done vs pending), '## Open Questions', '## References' (files, CRs, tickets, links). Output ONLY the markdown document.")
    [[ -z "$gen" ]] && { echo "spec generation produced no output"; return 1; }
    mkdir -p "$cdir"; print -r -- "$gen" > "$cfile"
  else
    print -u2 -- $'\e[2m(cached spec — ccspec -r "'"$match_name"$'" to refresh)\e[0m'
    [[ "${tf[1]}" -nt "$cfile" ]] && print -u2 -- $'\e[2m(transcript changed since this spec; -r to refresh)\e[0m'
  fi
  cp -- "$cfile" "$out" || { echo "failed to write $out"; return 1; }
  print -u2 -- $'\e[2m(spec written: '"$out"$')\e[0m'
  cat -- "$out"
}

ccexplain() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccexplain; return 0; }
  local q extra=""
  if [[ -n "${1-}" ]]; then q="$1"; shift; extra="$*"
  else _cc_pick_name; case $? in 2) echo 'usage: ccexplain "<name>" [extra]'; return 2;; 1) return 1;; esac; q=$_CC_SEL_NAME; fi
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" name id match_id match_name
  while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  if [[ -z $match_id ]]; then
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
  (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)."; return 1; }
  command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH."; return 1; }
  print -u2 "Explaining '$match_name' ($match_id)…"
  claude -p --no-session-persistence "Read the Claude Code session transcript (JSONL) at ${tf[1]} and explain it in simple, plain terms for someone new to it. Use exactly three sections: '## Done' (what was accomplished), '## Pending' (what's unfinished / in progress), '## Next' (what should be done next). Keep it concrete and jargon-light. ${extra}"
}

ccexport() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccexport; return 0; }
  local q out
  if [[ -n "${1-}" ]]; then q="$1"; out="${2-}"
  else _cc_pick_name; case $? in 2) echo 'usage: ccexport "<name>" [output.md]'; return 2;; 1) return 1;; esac; q=$_CC_SEL_NAME; out=""; fi
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" name id match_id match_name
  while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  if [[ -z $match_id ]]; then
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
  (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)."; return 1; }
  command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH."; return 1; }
  if [[ -z "$out" ]]; then
    local slug; slug=$(print -r -- "${match_name:l}" | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')
    out="./${slug}.context.md"
  fi
  print -u2 "Exporting '$match_name' -> $out …"
  claude -p --no-session-persistence "Read the Claude Code session transcript (JSONL) at ${tf[1]} and write a Markdown CONTEXT EXPORT for handoff. Sections: '# <Title>', '## Overview', '## What happened' (chronological key points), '## Decisions', '## Current state', '## References' (files, CRs, tickets, links). Output ONLY the markdown document." > "$out"
  [[ -s "$out" ]] && echo "Exported: $out" || { echo "export produced no output"; rm -f "$out"; return 1; }
}

ccnote() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccnote; return 0; }
  local q newnotes
  if [[ -n "${1-}" ]]; then
    q="$1"; (( $# < 2 )) && { echo 'usage: ccnote "<name>" "<new notes>"'; return 2; }; newnotes="$2"
  else
    _cc_pick_name; case $? in 2) echo 'usage: ccnote "<name>" "<new notes>"'; return 2;; 1) return 1;; esac
    q=$_CC_SEL_NAME
    read "newnotes?New notes for '$q': "
    [[ -z "$newnotes" ]] && { echo "aborted (empty notes)"; return 1; }
  fi
  [[ "$newnotes" == *'|'* ]] && { echo "notes cannot contain '|'"; return 2; }
  local -a exact sub; local name id
  while IFS=$'\t' read -r name id; do
    [[ "${name:l}" == "${q:l}" ]]   && exact+=("$name")
    [[ "${name:l}" == *"${q:l}"* ]] && sub+=("$name")
  done < <(_cc_rows)
  local -a matches
  if (( ${#exact} )); then matches=("${exact[@]}"); else matches=("${sub[@]}"); fi
  (( ${#matches} == 0 )) && { echo "No entry matching '$q'."; return 1; }
  if (( ${#matches} > 1 )); then
    echo "'$q' is ambiguous — matches multiple entries. Be more specific:"
    local m; for m in "${matches[@]}"; do echo "  - $m"; done; return 1
  fi
  local target=${matches[1]}
  local tmp="${_CC_MAP}.tmp.$$"
  awk -F'|' -v t="$target" -v nn="$newnotes" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
    { if ($0 ~ /^\|/ && $0 ~ /`/ && trim($2)==t) { print "| " trim($2) " | " trim($3) " | " nn " |"; next } print }
  ' "$_CC_MAP" > "$tmp" && mv "$tmp" "$_CC_MAP" \
    && echo "Updated notes for '$target'." || { echo "update failed"; rm -f "$tmp"; return 1; }
}

# Emit "id<TAB>label" for every transcript NOT already in the map, newest first.
_cc_all_sessions() {
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local -a mapped; mapped=(${(f)"$(_cc_rows | cut -f2)"})
  local f id cwd prev mt
  for f in ${(f)"$(ls -t "$base"/projects/*/*.jsonl 2>/dev/null)"}; do
    [[ -z $f ]] && continue
    id=${${f:t}:r}
    (( ${mapped[(I)$id]} )) && continue    # skip already-mapped
    _cc_is_ephemeral "$f" && continue      # skip Claudius' own one-shots / seeded sessions
    cwd=$(grep -m1 -oE '"cwd":"[^"]*"' "$f" 2>/dev/null | sed 's/"cwd":"//; s/"$//')
    prev=$(grep -m1 '"type":"user"' "$f" 2>/dev/null | grep -oE '"content":"[^"]*"' | head -1 | sed 's/"content":"//; s/"$//')
    mt=$(_cc_mtime_fmt "$f")
    print -r -- "$id	${mt} · ${cwd:t} · ${prev:0:60}"
  done
}

ccimport() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccimport; return 0; }
  local allmode=; [[ "${1-}" == -a || "${1-}" == --all ]] && allmode=1   # --all: name every unmapped session
  local -a ids labels
  local id lbl
  while IFS=$'\t' read -r id lbl; do ids+=("$id"); labels+=("$lbl"); done < <(_cc_all_sessions)
  (( ${#ids} == 0 )) && { echo "No unmapped sessions to import."; return 0; }
  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "Unmapped sessions (run ccimport in an interactive terminal to pick):"
    local i; for (( i=1; i<=${#ids}; i++ )); do printf "  %s  %s\n" "${ids[i]}" "${labels[i]}"; done
    return 0
  fi
  local n=${#ids}
  local -a checked; local i; for (( i=1; i<=n; i++ )); do checked[i]=$([[ -n $allmode ]] && echo 1 || echo 0); done
  if [[ -z $allmode ]]; then                             # interactive multi-select picker (skipped by --all)
  local filter="" key seq sel=1 drawn=0 cancelled=
  local -a fidx
  local _recompute _draw
  _recompute() {   # filter on label (date · workspace · preview); keep checks by real index
    fidx=(); local i lf="${filter:l}"
    for (( i=1; i<=n; i++ )); do
      [[ -z $lf || "${labels[i]:l}" == *"$lf"* ]] && fidx+=($i)
    done
    (( sel < 1 )) && sel=1
    if (( ${#fidx} == 0 )); then sel=0; elif (( sel > ${#fidx} )); then sel=${#fidx}; fi
  }
  _draw() {
    (( drawn > 0 )) && printf '\e[%dA\r\e[J' "$drawn" >&2
    printf '\e[1mImport\e[0m \e[2mfilter:\e[0m %s\e[7m \e[0m \e[2m(type · ↑/↓ · Space tick · Enter · Esc)\e[0m\n' "$filter" >&2
    local shown=1 j real box
    if (( ${#fidx} == 0 )); then
      printf '  \e[2m(no matches)\e[0m\n' >&2; (( shown++ ))
    else
      for (( j=1; j<=${#fidx}; j++ )); do
        real=${fidx[j]}
        [[ ${checked[real]} == 1 ]] && box='[x]' || box='[ ]'
        if (( j==sel )); then printf '  \e[7m%s %s\e[0m\n' "$box" "${labels[real]}" >&2
        else printf '  %s \e[36m%s\e[0m\n' "$box" "${labels[real]}" >&2; fi
        (( shown++ ))
      done
    fi
    drawn=$shown
  }
  tput civis 2>/dev/null
  _recompute; _draw
  while true; do
    read -rsk1 key
    case $key in
      $'\e') seq=''; read -rsk2 -t 0.4 seq 2>/dev/null   # reset so a lone Esc isn't mistaken for a stale arrow
        case $seq in
          '[A'|'OA') (( sel>1 )) && (( sel-- ));;
          '[B'|'OB') (( sel<${#fidx} )) && (( sel++ ));;
          '') if [[ -n $filter ]]; then filter=""; sel=1; _recompute; else cancelled=1; break; fi;;
        esac;;
      ' ') (( ${#fidx}>=1 )) && { local r=${fidx[sel]}; checked[r]=$(( 1 - checked[r] )); };;
      $'\n'|$'\r') break;;
      $'\x7f'|$'\b') filter="${filter%?}"; sel=1; _recompute;;
      *) [[ $key == [[:print:]] && $key != ' ' ]] && { filter+="$key"; sel=1; _recompute; };;
    esac
    _draw
  done
  tput cnorm 2>/dev/null
  [[ -n $cancelled ]] && { print -u2 "cancelled"; return 1; }
  fi                                                     # end interactive picker (--all pre-checks all)
  [[ -n $allmode ]] && print -u2 -- $'\e[2mNaming all '"${#ids}"$' unmapped chat(s) — Enter accepts each suggestion · '"'"'-'"'"' skips.\e[0m'
  local added=0 nm
  local -a picks=(); for (( i=1; i<=n; i++ )); do [[ ${checked[i]} == 1 ]] && picks+=($i); done
  (( ${#picks} == 0 )) && { echo "Nothing selected."; return 0; }
  # suggest a name for each pick (parallel; via claude, from the chat's first message)
  local -A sugg=()
  if command -v claude >/dev/null 2>&1; then
    setopt local_options no_monitor
    print -u2 -- $'\e[2mSuggesting names for '"${#picks}"$' chat(s)…\e[0m'
    local tmpd; tmpd=$(mktemp -d 2>/dev/null || echo "/tmp/ccimport.$$"); mkdir -p "$tmpd"
    local idx msg
    for idx in $picks; do
      msg=${labels[idx]##*· }   # the first-message part of the preview label
      ( claude -p --no-session-persistence "Suggest a concise 2–5 word Title Case name for a saved coding chat that begins with the message below. Output ONLY the name — no quotes, punctuation, or explanation."$'\n\n'"Message: ${msg}" > "$tmpd/$idx" 2>/dev/null ) &
    done
    wait
    for idx in $picks; do
      sugg[$idx]=$(print -r -- "$(<"$tmpd/$idx" 2>/dev/null)" | head -1 | sed 's/[`|"]//g; s/^[[:space:]]*//; s/[[:space:]]*$//')
      sugg[$idx]=${sugg[$idx][1,48]}
    done
    rm -rf "$tmpd"
  fi
  local idx s key rest seq2 cancelled=
  for idx in $picks; do
    print -u2 -- $'\e[2m'"${labels[idx]}"$'\e[0m'
    s=${sugg[$idx]-}
    if [[ -n $s ]]; then
      print -n -u2 -- "  Name for ${ids[idx]:0:8}…  suggested "$'\e[36m'"$s"$'\e[0m'"  — Enter accepts · '-' skips · Esc quits · or type: "
    else
      print -n -u2 -- "  Name for ${ids[idx]:0:8}…  — type a name · '-'/Enter skips · Esc quits: "
    fi
    nm=; IFS= read -rsk1 key                              # read one raw key to branch on
    case "$key" in
      $'\e') seq2=; read -rsk2 -t 0.3 seq2 2>/dev/null; print -u2 ""
             [[ -z $seq2 ]] && { cancelled=1; break; }    # lone Esc -> quit the whole run
             nm='-' ;;                                    # an escape sequence (e.g. arrow) -> skip this one
      $'\n'|$'\r') print -u2 ""; nm=$s ;;                 # Enter -> accept the suggestion (empty if none)
      '-') print -u2 -- '-'; nm='-' ;;
      $'\x7f'|$'\b') print -u2 ""; nm='-' ;;
      *) print -u2 -n -- "$key"; IFS= read -r rest; nm="$key$rest" ;;   # typed name: echo 1st key, read the rest
    esac
    [[ "$nm" == "-" || -z $nm ]] && { echo "skipped ${ids[idx]:0:8}"; continue; }
    ccadd "$nm" "${ids[idx]}" && (( added++ ))
  done
  [[ -n $cancelled ]] && print -u2 -- $'\e[2mcancelled — stopped after naming '"$added"$'.\e[0m'
  echo "Imported $added session(s)."
}

ccremove() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccremove; return 0; }
  local assume_yes= q
  [[ "${1-}" == "-y" ]] && { assume_yes=1; shift; }
  if [[ -n "${1-}" ]]; then q="${1-}"
  else _cc_pick_name; case $? in 2) echo "usage: ccremove [-y] \"<conversation name>\""; return 2;; 1) return 1;; esac; q=$_CC_SEL_NAME; fi
  local -a exact sub; local name id
  while IFS=$'\t' read -r name id; do
    [[ "${name:l}" == "${q:l}" ]]   && exact+=("$name")
    [[ "${name:l}" == *"${q:l}"* ]] && sub+=("$name")
  done < <(_cc_rows)
  local -a matches
  if (( ${#exact} )); then matches=("${exact[@]}"); else matches=("${sub[@]}"); fi
  (( ${#matches} == 0 )) && { echo "No entry matching '$q'."; return 1; }
  if (( ${#matches} > 1 )); then
    echo "'$q' is ambiguous — matches multiple entries. Be more specific:"
    local m; for m in "${matches[@]}"; do echo "  - $m"; done; return 1
  fi
  local target=${matches[1]}
  if [[ -z $assume_yes ]]; then
    printf "Remove '%s' from the map? [y/N] " "$target"
    local ans; read -r ans
    [[ "$ans" == [yY]* ]] || { echo "aborted"; return 1; }
  fi
  local tmp="${_CC_MAP}.tmp.$$"
  awk -F'|' -v t="$target" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
    { if ($0 ~ /^\|/ && $0 ~ /`/ && trim($2) == t) next; print }
  ' "$_CC_MAP" > "$tmp" && mv "$tmp" "$_CC_MAP" \
    && echo "Removed '$target'." || { echo "removal failed"; rm -f "$tmp"; return 1; }
}

ccadd() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccadd; return 0; }
  local name="${1-}" id="${2-}" notes="${3-}"
  [[ -z "$name" ]] && { echo 'usage: ccadd "<name>" [<session-id>] ["<notes>"]'; return 2; }
  [[ "$name" == *'|'* || "$name" == *'`'* ]] && { echo "name cannot contain '|' or a backtick"; return 2; }
  [[ -z "$id" ]] && id="${CLAUDE_CODE_SESSION_ID-}"  # inside a session: default to current
  [[ -z "$id" ]] && { echo "no id given and CLAUDE_CODE_SESSION_ID is unset — pass the id, or run inside a session"; return 2; }
  if [[ ! "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "id doesn't look like a session UUID: $id"; return 2
  fi
  local n i
  while IFS=$'\t' read -r n i; do
    [[ "$i" == "$id" ]]           && { echo "id already mapped as '$n' (use ccrename to relabel)."; return 1; }
    [[ "${n:l}" == "${name:l}" ]] && { echo "name '$n' already exists."; return 1; }
  done < <(_cc_rows)
  local newrow; printf -v newrow '| %s | `%s` | %s |' "$name" "$id" "$notes"
  local tmp="${_CC_MAP}.tmp.$$"
  awk -v row="$newrow" '
    /^\|/ { last=NR } { line[NR]=$0 }
    END { for (i=1;i<=NR;i++){ print line[i]; if (i==last) print row } }
  ' "$_CC_MAP" > "$tmp" && mv "$tmp" "$_CC_MAP" \
    && echo "Added '$name' -> $id" || { echo "add failed"; rm -f "$tmp"; return 1; }
}

ccrename() {
  [[ "${1-}" == -h || "${1-}" == --help ]] && { _cc_help ccrename; return 0; }
  local old new
  if [[ -n "${1-}" ]]; then
    old="$1"; [[ -z "${2-}" ]] && { echo 'usage: ccrename "<old name>" "<new name>"'; return 2; }; new="$2"
  else
    _cc_pick_name; case $? in 2) echo 'usage: ccrename "<old name>" "<new name>"'; return 2;; 1) return 1;; esac
    old=$_CC_SEL_NAME
    read "new?New name for '$old': "
    [[ -z "$new" ]] && { echo "aborted (empty name)"; return 1; }
  fi
  [[ "$new" == *'|'* || "$new" == *'`'* ]] && { echo "new name cannot contain '|' or a backtick"; return 2; }
  local -a exact sub; local name id
  while IFS=$'\t' read -r name id; do
    [[ "${name:l}" == "${old:l}" ]]   && exact+=("$name")
    [[ "${name:l}" == *"${old:l}"* ]] && sub+=("$name")
  done < <(_cc_rows)
  local -a matches
  if (( ${#exact} )); then matches=("${exact[@]}"); else matches=("${sub[@]}"); fi
  (( ${#matches} == 0 )) && { echo "No entry matching '$old'."; return 1; }
  if (( ${#matches} > 1 )); then
    echo "'$old' is ambiguous — matches multiple entries. Be more specific:"
    local m; for m in "${matches[@]}"; do echo "  - $m"; done; return 1
  fi
  local target=${matches[1]}
  while IFS=$'\t' read -r name id; do
    [[ "${name:l}" == "${new:l}" && "$name" != "$target" ]] && { echo "An entry named '$name' already exists."; return 1; }
  done < <(_cc_rows)
  local tmp="${_CC_MAP}.tmp.$$"
  awk -F'|' -v old="$target" -v new="$new" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
    BEGIN{OFS="|"}
    { if ($0 ~ /^\|/ && $0 ~ /`/ && trim($2)==old) { $2=" " new " "; print; next } print }
  ' "$_CC_MAP" > "$tmp" && mv "$tmp" "$_CC_MAP" \
    && echo "Renamed '$target' -> '$new'." || { echo "rename failed"; rm -f "$tmp"; return 1; }
}

# --- zsh tab-completion of conversation names (needs compinit loaded) ---
if (( $+functions[compdef] )); then
  _cc_complete_names() {
    local -a names matched
    names=(${(f)"$(_cc_rows | cut -f1)"})
    local cur="${(L)PREFIX-}${(L)SUFFIX-}"     # what's typed so far, lowercased
    if [[ -n $cur ]]; then
      local n; for n in $names; do [[ "${(L)n}" == *"$cur"* ]] && matched+=("$n"); done
    else
      matched=($names)
    fi
    (( ${#matched} )) || return 1
    # menu insert: cycle full names on TAB instead of inserting an (empty) common prefix,
    # which would otherwise wipe the typed text for substring matches. -U = replace whole word.
    compstate[insert]=menu
    compadd -U -a matched
  }
  _cc_no_complete() { }                      # no name arg -> suppress default file completion
  compdef _cc_complete_names ccresume ccbranch ccremove ccrename ccnote ccfetch ccspec ccfind ccexplain ccexport ccask
  compdef _cc_no_complete ccadd ccimport ccmonitor ccname ccplay claudius cchelp cccache cccleanup
fi
