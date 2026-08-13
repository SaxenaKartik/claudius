# Claudius — manage Claude Code conversations by name (reads the session map)
# Enable by adding to ~/.zshrc:  source ~/.claude/claudius.zsh
#
#   ccname                        print THIS chat's name in the map (uses $CLAUDE_CODE_SESSION_ID)
#   ccplay [game]                 mini games while Claude thinks (no arg = menu; guess/rps/flip/roll/react)
#   cclist                        interactive picker (type to filter, ↑/↓, Enter resumes, Esc clear/quit; -l = plain list)
#   ccresume "<name>"             resume by name (exact -> case-insensitive -> substring; no arg opens picker)
#   ccfind "<text>"               search names + notes for a substring
#   ccimport                      pick unmapped sessions (multi-select) and name them into the map
#   ccmonitor [N]                 table of recent chats: tokens (out/ctx), age, status (working/waiting/inactive)
#   ccfetch "<name>" [extra]      summarise another chat's context (one-shot `claude -p`, reads transcript)
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

cchelp() {
  print -r -- $'\e[1mClaudius\e[0m — manage Claude Code conversations by name'
  print -r -- "  map: $_CC_MAP"
  print
  printf '  \e[36m%-33s\e[0m %s\n' 'ccname'                        'print THIS chat'\''s name in the map'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccplay [game]'                 'mini games while Claude thinks (no arg = menu)'
  printf '  \e[36m%-33s\e[0m %s\n' 'cclist'                        'picker: type to filter · ↑/↓ · Enter resume · Esc clear/quit'
  printf '  \e[36m%-33s\e[0m %s\n' 'cclist -l'                     'plain list (name + id)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccresume "<name>"'             'resume by name (exact → case-insensitive → substring)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccfind "<text>"'               'search names + notes for a substring'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccimport'                      'multi-select unmapped sessions → name them into the map'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccmonitor [N]'                 'table of recent chats: tokens, age, status'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccfetch "<name>" [extra]'      'summarise another chat'\''s context (claude -p on its transcript)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccspec "<name>" [out.md]'      'write a spec file (goal/decisions/tasks) for a chat'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccexplain "<name>" [extra]'    'plain-terms explanation: Done / Pending / Next'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccexport "<name>" [out.md]'    'write a context markdown file for a chat'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccnote "<name>" "<notes>"'     'replace an entry'\''s notes'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccadd "<name>" [id] ["notes"]' 'add a row (id defaults to $CLAUDE_CODE_SESSION_ID)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccrename "<old>" "<new>"'      'rename a key (session id preserved)'
  printf '  \e[36m%-33s\e[0m %s\n' 'ccremove [-y] "<name>"'        'remove a row (confirms; refuses ambiguous)'
  printf '  \e[36m%-33s\e[0m %s\n' 'cchelp'                        'show this help'
  print
  print -r -- $'  \e[2mIn a chat: /ccadd /ccname /ccfetch /ccspec /ccexplain /ccexport\e[0m'
  print -r -- $'  \e[2mPickers (cclist, ccimport, any name cmd with no arg): type to filter · ↑/↓ · Esc clears\e[0m'
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
  local id="${1-}" cwd
  cwd=$(_cc_cwd_for_id "$id")
  if [[ -n $cwd && $cwd != $PWD ]]; then
    echo "(cd $cwd) claude --resume $id"
    (cd "$cwd" && claude --resume "$id")
  else
    claude --resume "$id"
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
      $'\e') read -rsk2 -t 0.4 seq 2>/dev/null
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
ccplay() {   # mini games to pass the time while Claude thinks (no session impact)
  local -a games=(guess rps flip roll react)
  typeset -A _cc_g_desc _cc_g_instr
  _cc_g_desc=(
    guess "Hi-Lo — guess a hidden number 1–100"
    rps   "Rock–paper–scissors vs the computer"
    flip  "Flip a coin"
    roll  "Roll two dice"
    react "Reaction timer — how fast can you hit a key?"
  )
  _cc_g_instr=(
    guess "I picked a number 1–100. Type a guess and Enter; I'll say ↑ higher / ↓ lower. q quits."
    rps   "Type r, p, or s and Enter. I pick secretly, then we compare."
    flip  "Just watch — heads or tails."
    roll  "Just watch — two six-sided dice."
    react "Press any key to start. When you see GO!, hit any key as fast as you can."
  )
  local g="${1-}"
  if [[ -z $g ]]; then
    printf '\e[1m🎮 Pick a game\e[0m\n'
    local i
    for (( i=1; i<=${#games}; i++ )); do
      printf '  \e[36m%d\e[0m) \e[1m%-6s\e[0m \e[2m%s\e[0m\n' "$i" "${games[i]}" "${_cc_g_desc[${games[i]}]}"
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

ccresume() {
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

ccfind() {
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
      mt=$(stat -f '%m' "$f" 2>/dev/null)
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

ccfetch() {
  # Usage:
  #   ccfetch "<name>" [extra]           summarise a mapped chat via claude -p on its transcript
  #   ccfetch --file path.md [extra]     summarise an ARBITRARY markdown/text file
  #   ccfetch @path.md [extra]           shorthand for --file
  command -v claude >/dev/null 2>&1 || { echo "claude not found on PATH."; return 1; }
  local q="${1-}" src srcdesc extra="" picked=
  if [[ -z "$q" ]]; then
    _cc_pick_name; case $? in 2) echo 'usage: ccfetch "<name>" [extra]  |  ccfetch --file <path.md> [extra]  |  ccfetch @<path.md> [extra]'; return 2;; 1) return 1;; esac
    q=$_CC_SEL_NAME; picked=1
  fi
  if [[ -z $picked && ( "$q" == "--file" || "$q" == "-f" ) ]]; then
    src="${2-}"; [ -z "$src" ] && { echo "usage: ccfetch --file <path.md> [extra]"; return 2; }
    shift 2; extra="$*"
  elif [[ -z $picked && "$q" == @* ]]; then
    src="${q#@}"; shift; extra="$*"
  fi
  if [[ -n $src ]]; then
    [[ -r "$src" ]] || { echo "File not readable: $src"; return 1; }
    srcdesc="file $src"
    print -u2 "Summarising $srcdesc…"
    claude -p "Read the document at $src and produce a concise summary in short bullet points: goal/context, key decisions, current state, open next steps, important references. ${extra}"
    return
  fi
  # name mode
  [[ -z $picked ]] && { shift; extra="$*"; }
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" name id match_id match_name
  while IFS=$'\t' read -r name id; do [[ "${name:l}" == "${q:l}" ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  if [[ -z $match_id ]]; then
    while IFS=$'\t' read -r name id; do [[ "${name:l}" == *"${q:l}"* ]] && { match_id=$id; match_name=$name; break; }; done < <(_cc_rows)
  fi
  [[ -z $match_id ]] && { echo "No session matching '$q'. Known:"; _cc_plain; return 1; }
  local -a tf; tf=( "$base"/projects/*/"$match_id.jsonl"(N) )
  (( ${#tf} == 0 )) && { echo "No transcript on disk for '$match_name' ($match_id)."; return 1; }
  print -u2 "Summarising '$match_name' ($match_id)…"
  claude -p "Read the Claude Code session transcript (JSONL) at ${tf[1]} and produce a concise handoff summary of that conversation: goal, key decisions/answers, current state, open next steps, and important file/CR/ticket references. Use short bullet points. ${extra}"
}

ccspec() {
  local q out
  if [[ -n "${1-}" ]]; then q="$1"; out="${2-}"
  else _cc_pick_name; case $? in 2) echo 'usage: ccspec "<name>" [output.md]'; return 2;; 1) return 1;; esac; q=$_CC_SEL_NAME; out=""; fi
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local name id match_id match_name
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
    out="./${slug}.spec.md"
  fi
  print -u2 "Writing spec for '$match_name' -> $out …"
  claude -p "Read the Claude Code session transcript (JSONL) at ${tf[1]} and write a SPEC document in Markdown for this work. Sections: '# <Title>', '## Goal / Context', '## Key Decisions', '## Tasks' (as - [ ] / - [x] checkbox items covering the work involved, done vs pending), '## Open Questions', '## References' (files, CRs, tickets, links). Output ONLY the markdown document." > "$out"
  [[ -s "$out" ]] && echo "Spec written: $out" || { echo "spec generation produced no output"; rm -f "$out"; return 1; }
}

ccexplain() {
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
  claude -p "Read the Claude Code session transcript (JSONL) at ${tf[1]} and explain it in simple, plain terms for someone new to it. Use exactly three sections: '## Done' (what was accomplished), '## Pending' (what's unfinished / in progress), '## Next' (what should be done next). Keep it concrete and jargon-light. ${extra}"
}

ccexport() {
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
  claude -p "Read the Claude Code session transcript (JSONL) at ${tf[1]} and write a Markdown CONTEXT EXPORT for handoff. Sections: '# <Title>', '## Overview', '## What happened' (chronological key points), '## Decisions', '## Current state', '## References' (files, CRs, tickets, links). Output ONLY the markdown document." > "$out"
  [[ -s "$out" ]] && echo "Exported: $out" || { echo "export produced no output"; rm -f "$out"; return 1; }
}

ccnote() {
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
    cwd=$(grep -m1 -oE '"cwd":"[^"]*"' "$f" 2>/dev/null | sed 's/"cwd":"//; s/"$//')
    prev=$(grep -m1 '"type":"user"' "$f" 2>/dev/null | grep -oE '"content":"[^"]*"' | head -1 | sed 's/"content":"//; s/"$//')
    mt=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f" 2>/dev/null)
    print -r -- "$id	${mt} · ${cwd:t} · ${prev:0:60}"
  done
}

ccimport() {
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
  local -a checked; local i; for (( i=1; i<=n; i++ )); do checked[i]=0; done
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
      $'\e') read -rsk2 -t 0.4 seq 2>/dev/null
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
  local added=0 nm
  for (( i=1; i<=n; i++ )); do
    [[ ${checked[i]} == 1 ]] || continue
    print -u2 -- $'\e[2m'"${labels[i]}"$'\e[0m'
    read "nm?Name for ${ids[i]:0:8}… (blank skips): "
    [[ -z $nm ]] && { echo "skipped ${ids[i]}"; continue; }
    ccadd "$nm" "${ids[i]}" && (( added++ ))
  done
  echo "Imported $added session(s)."
}

ccremove() {
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
  compdef _cc_complete_names ccresume ccremove ccrename ccnote ccfetch ccspec ccfind ccexplain ccexport
  compdef _cc_no_complete ccadd ccimport ccmonitor ccname ccplay
fi
