#!/usr/bin/env zsh
# Rigorous, self-contained test suite for cc-resume.
# Installs the bundled installer into a throwaway sandbox (never touches your real
# ~/.claude, map, or ~/.zshrc), seeds fake workspaces/transcripts, stubs `claude`,
# and asserts every command + edge case. Runs under `nounset` to prove robustness.
#
#   zsh test.zsh        # exit 0 = all pass
emulate -L zsh
setopt no_unset          # prove functions are nounset-safe
INSTALLER="${0:A:h}/install.sh"   # POSIX installer next to this script

PASS=0; FAIL=0
ok(){ if [[ "$2" == "$3" ]]; then ((PASS++)); else ((FAIL++)); print "FAIL: $1\n   expected: [$2]\n   actual:   [$3]"; fi }
okc(){ if [[ "$3" == *"$2"* ]]; then ((PASS++)); else ((FAIL++)); print "FAIL: $1\n   want contains: [$2]\n   actual:       [$3]"; fi }
okn(){ if [[ "$3" != *"$2"* ]]; then ((PASS++)); else ((FAIL++)); print "FAIL: $1\n   must NOT contain: [$2]\n   actual: [$3]"; fi }
okrc(){ if [[ "$2" == "$3" ]]; then ((PASS++)); else ((FAIL++)); print "FAIL(rc): $1 expected exit $2 got $3"; fi }

# ---- isolated sandbox ----
SB=$(mktemp -d)
export CLAUDE_CONFIG_DIR="$SB/.claude"; export ZDOTDIR="$SB"; touch "$SB/.zshrc"
export CC_MAP="$CLAUDE_CONFIG_DIR/cc_map.md"
sh "$INSTALLER" >/dev/null

# fake workspaces + transcripts (for cwd resolution / launch)
WSA="$SB/wsA"; WSB="$SB/wsB"; mkdir -p "$WSA" "$WSB"
idA=aaaaaaaa-1111-2222-3333-444444444444
idB=bbbbbbbb-5555-6666-7777-888888888888
idC=cccccccc-1111-2222-3333-444444444444
idG=dddddddd-9999-eeee-ffff-000000000000   # ghost: mapped but NO transcript
idU=eeeeeeee-1111-2222-3333-444444444444   # on-disk transcript, never mapped -> import candidate
mkdir -p "$CLAUDE_CONFIG_DIR/projects/pA" "$CLAUDE_CONFIG_DIR/projects/pB" "$CLAUDE_CONFIG_DIR/projects/pC"
print -r -- '{"type":"summary","cwd":"'"$WSA"'","usage":{"output_tokens":5000}}' > "$CLAUDE_CONFIG_DIR/projects/pA/$idA.jsonl"
print -r -- '{"type":"summary","cwd":"'"$WSB"'","usage":{"output_tokens":12000}}' > "$CLAUDE_CONFIG_DIR/projects/pB/$idB.jsonl"
print -r -- '{"type":"user","message":{"role":"user","content":"import me please preview text"},"cwd":"'"$WSA"'"}' > "$CLAUDE_CONFIG_DIR/projects/pC/$idU.jsonl"

unset CLAUDE_CODE_SESSION_ID   # isolate: don't inherit the real session's id
_CC_COMPDEF_ARGS=""; compdef(){ _CC_COMPDEF_ARGS+=" $*"; }   # stub accumulates registrations
source "$CLAUDE_CONFIG_DIR/claudius.zsh"
claude(){ print -r -- "CLAUDE $* @ $PWD"; }   # stub (overrides PATH); prints all args

print "===== ccadd ====="
out=$(ccadd "Alpha" "$idA" "first note"); okc "ccadd Alpha" "Added 'Alpha' -> $idA" "$out"
out=$(ccadd "Beta"  "$idB" "second");     okc "ccadd Beta"  "Added 'Beta' -> $idB"  "$out"
out=$(CLAUDE_CODE_SESSION_ID=$idC ccadd "EnvName"); okc "ccadd via env id" "Added 'EnvName' -> $idC" "$out"
out=$(ccadd "Ghost" "$idG");              okc "ccadd Ghost (no transcript)" "Added 'Ghost' -> $idG" "$out"
out=$(ccadd "Dup" "$idA");                okc "ccadd dup id refused" "id already mapped as 'Alpha'" "$out"
out=$(ccadd "alpha" "11111111-2222-3333-4444-555555555555"); okc "ccadd dup name (ci) refused" "name 'Alpha' already exists" "$out"
out=$(ccadd "Bad" "not-a-uuid");          okc "ccadd bad uuid" "doesn't look like a session UUID" "$out"
out=$(ccadd "Pipe|Name" "$idA");          okc "ccadd name with pipe" "cannot contain '|'" "$out"
out=$(ccadd);                             okc "ccadd no args usage" "usage: ccadd" "$out"
out=$(ccadd "NoId");                      okc "ccadd no id, no env" "CLAUDE_CODE_SESSION_ID is unset" "$out"
ccadd "NoId" 2>/dev/null; okrc "ccadd no-id exit code" 2 $?

print "===== map integrity after adds ====="
n=$(_cc_rows | wc -l | tr -d ' '); ok "_cc_rows count = 4" 4 "$n"
okc "row order preserved" "Alpha" "$(_cc_rows | sed -n 1p)"
last_row_ln=$(grep -nE '^\| .* \| `' "$CC_MAP" | tail -1 | cut -d: -f1)
prose_ln=$(grep -n 'Row format' "$CC_MAP" | head -1 | cut -d: -f1)
if (( last_row_ln < prose_ln )); then ((PASS++)); else ((FAIL++)); print "FAIL: rows leaked past prose ($last_row_ln !< $prose_ln)"; fi
okc "starter prose intact" "Row format" "$(cat "$CC_MAP")"

print "===== ccimport / _cc_all_sessions ====="
out=$(_cc_all_sessions)
okc "enumerates unmapped idU" "$idU" "$out"
okc "preview = first user message" "import me please" "$out"
okn "excludes mapped idA" "$idA" "$out"
okn "excludes mapped idB" "$idB" "$out"
out=$(ccimport </dev/null)
okc "ccimport non-tty header" "Unmapped sessions" "$out"
okc "ccimport non-tty lists idU" "$idU" "$out"

print "===== ccresume ====="
out=$(ccresume "Alpha");        okc "ccresume exact -> cd+launch" "CLAUDE --resume $idA @ $WSA" "$out"
out=$(ccresume "alpha");        okc "ccresume case-insensitive" "$idA" "$out"
out=$(ccresume "bet");          okc "ccresume substring -> Beta" "$idB" "$out"
out=$(ccresume "Ghost");        okc "ccresume ghost launches w/o cd" "CLAUDE --resume $idG @" "$out"
out=$(ccresume "Ghost");        okn "ccresume ghost has no (cd ) line" "(cd " "$out"
out=$(ccresume "nope");         okc "ccresume no match" "No session matching 'nope'" "$out"
ccresume "nope" >/dev/null 2>&1; okrc "ccresume no-match exit" 1 $?

print "===== ccfind ====="
out=$(ccfind "Alpha");   okc "ccfind by name" "$idA" "$out"
out=$(ccfind "first");   okc "ccfind by notes" "Alpha" "$out"          # 'first note' lives in notes
out=$(ccfind "SECOND");  okc "ccfind case-insensitive notes" "Beta" "$out"
out=$(ccfind "e");       okc "ccfind multi-match returns >1" "Alpha" "$out"; okc "ccfind multi-match 2nd" "Beta" "$out"
out=$(ccfind "zzzznope"); okc "ccfind no match msg" "No entry matching" "$out"
ccfind "zzzznope" >/dev/null 2>&1; okrc "ccfind no-match exit" 1 $?
ccfind >/dev/null 2>&1; okrc "ccfind no-arg usage exit" 2 $?

print "===== ccname ====="
out=$(CLAUDE_CODE_SESSION_ID=$idA ccname); okc "ccname returns mapped name" "Alpha" "$out"
out=$(CLAUDE_CODE_SESSION_ID=99999999-9999-9999-9999-999999999999 ccname); okc "ccname unmapped session" "not in the map" "$out"
out=$(CLAUDE_CODE_SESSION_ID= ccname 2>&1); okc "ccname no session env" "not inside a Claude session" "$out"

print "===== ccmonitor ====="
out=$(ccmonitor); okc "ccmonitor header" "CONVERSATION" "$out"
okc "ccmonitor shows Alpha" "Alpha" "$out"
okc "ccmonitor shows token count" "K" "$out"

print "===== ccfetch ====="
out=$(ccfetch "Alpha");   okc "ccfetch invokes claude -p" " -p " "$out"
okc "ccfetch passes transcript path" "$idA.jsonl" "$out"
out=$(ccfetch "nope");    okc "ccfetch no match" "No session matching 'nope'" "$out"
ccfetch >/dev/null 2>&1;  okrc "ccfetch usage exit" 2 $?
# Beta Prime not renamed yet here (idB), transcript exists -> resolvable
out=$(ccfetch "Beta");    okc "ccfetch resolves Beta transcript" "$idB.jsonl" "$out"
# multi-name mode: 2+ names that ALL resolve -> one combined output with per-chat headers
out=$(ccfetch "Alpha" "Beta" </dev/null 2>/dev/null)
okc "ccfetch multi: Alpha header"     "# Alpha"    "$out"
okc "ccfetch multi: Beta header"      "# Beta"     "$out"
okc "ccfetch multi: Alpha transcript" "$idA.jsonl" "$out"
okc "ccfetch multi: Beta transcript"  "$idB.jsonl" "$out"
_cc_all_resolve "Alpha" "Beta"; okrc "_cc_all_resolve all match" 0 $?
_cc_all_resolve "Alpha" "nope"; okrc "_cc_all_resolve one miss" 1 $?
_cc_pick_names </dev/null >/dev/null 2>&1; okrc "_cc_pick_names non-TTY -> 2" 2 $?
# a name + non-name arg stays SINGLE (treated as extra), not multi
out=$(ccfetch "Alpha" fooextra </dev/null 2>/dev/null); okc "ccfetch single+extra not multi" "fooextra" "$out"

print "===== ccask ====="
# default mode: reads the FULL transcript(s)
out=$(ccask "what did we decide" "Alpha" </dev/null 2>/dev/null); okc "ccask embeds the question" "what did we decide" "$out"
okc "ccask default reads transcripts" "TRANSCRIPTS:" "$out"
okc "ccask points at a compact .text.md extract" ".text.md" "$out"
okc "ccask instructs a CANNOT ANSWER fallback" "CANNOT ANSWER" "$out"
# summary mode (-s): answers from cached summaries instead
out=$(ccask -s "what did we decide" "Alpha" </dev/null 2>/dev/null); okc "ccask -s uses summaries" "CONVERSATION SUMMARIES" "$out"
ccask </dev/null >/dev/null 2>&1; okrc "ccask no-question usage exit" 2 $?
out=$(ccask "q" "nope-nope" </dev/null 2>&1); okc "ccask unknown chat" "No session matching" "$out"
# -a: cross-chat search over ALL sessions (idU transcript contains 'preview')
out=$(ccask -a "preview" </dev/null 2>&1);       okc "ccask -a searches all chats" "MULTIPLE past coding chats" "$out"
out=$(ccask -a "zznomatchword" </dev/null 2>&1); okc "ccask -a no match" "none of your saved chats" "$out"

print "===== ccspec ====="
spec="$SB/alpha.spec.md"
out=$(ccspec "Alpha" "$spec"); okc "ccspec prints spec to stdout" "$idA.jsonl" "$out"
err=$(ccspec "Alpha" "$spec" 2>&1 >/dev/null); okc "ccspec reports written on stderr" "spec written: $spec" "$err"
okc "spec file invoked claude -p" " -p " "$(cat "$spec")"
okc "spec references transcript" "$idA.jsonl" "$(cat "$spec")"
( cd "$SB"; ccspec "Beta" >/dev/null ); [[ -f "$SB/beta.spec.md" ]]; okrc "ccspec default path -> <slug>.spec.md" 0 $?
out=$(ccspec "nope");     okc "ccspec no match" "No session matching 'nope'" "$out"
ccspec >/dev/null 2>&1;   okrc "ccspec usage exit" 2 $?

print "===== ccexplain ====="
out=$(ccexplain "Alpha");   okc "ccexplain invokes claude -p" " -p " "$out"
okc "ccexplain passes transcript path" "$idA.jsonl" "$out"
out=$(ccexplain "nope");    okc "ccexplain no match" "No session matching 'nope'" "$out"
ccexplain </dev/null >/dev/null 2>&1; okrc "ccexplain no-arg (non-tty) usage exit" 2 $?

print "===== ccexport ====="
xf="$SB/alpha.context.md"
out=$(ccexport "Alpha" "$xf"); okc "ccexport reports written" "Exported: $xf" "$out"
okc "ccexport file has claude -p" " -p " "$(cat "$xf")"
out=$(ccexport "nope");     okc "ccexport no match" "No session matching 'nope'" "$out"
ccexport </dev/null >/dev/null 2>&1; okrc "ccexport no-arg (non-tty) usage exit" 2 $?
okc "completion registered for ccexplain" "ccexplain" "${_CC_COMPDEF_ARGS-}"
okc "completion registered for ccexport"  "ccexport"  "${_CC_COMPDEF_ARGS-}"

print "===== _cc_cwd_for_id ====="
ok "cwd for idA" "$WSA" "$(_cc_cwd_for_id $idA)"
ok "cwd for idB" "$WSB" "$(_cc_cwd_for_id $idB)"
_cc_cwd_for_id $idG >/dev/null; okrc "cwd for ghost returns 1" 1 $?

print "===== cclist (non-TTY -> plain) ====="
out=$(cclist </dev/null);       okc "cclist plain lists Alpha" "Alpha" "$out"
out=$(cclist -l </dev/null);    okc "cclist -l lists Beta" "Beta" "$out"
out=$(ccresume </dev/null);     okc "ccresume no-arg -> plain list" "Alpha" "$out"

print "===== ccrename ====="
out=$(ccrename "Beta" "Beta Prime"); okc "ccrename ok" "Renamed 'Beta' -> 'Beta Prime'" "$out"
ok  "ccrename id preserved" "$idB" "$(_cc_rows | awk -F'\t' '$1=="Beta Prime"{print $2}')"
okn "old name gone" "	" "$(_cc_rows | awk -F'\t' '$1=="Beta"{print}')"
out=$(ccrename "Alpha" "Beta Prime"); okc "ccrename collision refused" "already exists" "$out"
out=$(ccrename "Alpha" "Bad|Name");   okc "ccrename illegal char" "cannot contain '|'" "$out"
out=$(ccrename "zzz" "Whatever");      okc "ccrename no match" "No entry matching 'zzz'" "$out"
n=$(_cc_rows | wc -l | tr -d ' '); ok "count still 4 after renames" 4 "$n"

print "===== ccremove ====="
out=$(printf 'n\n' | ccremove "Alpha"); okc "ccremove prompt n -> aborted" "aborted" "$out"
ok "Alpha still present after abort" "$idA" "$(_cc_rows | awk -F'\t' '$1=="Alpha"{print $2}')"
out=$(ccremove -y "Ghost");     okc "ccremove -y Ghost" "Removed 'Ghost'" "$out"
out=$(printf 'y\n' | ccremove "EnvName"); okc "ccremove prompt y" "Removed 'EnvName'" "$out"
n=$(_cc_rows | wc -l | tr -d ' '); ok "count = 2 after 2 removals" 2 "$n"
out=$(ccremove -y "nope");      okc "ccremove no match" "No entry matching 'nope'" "$out"
ccadd "Shared One" "11111111-1111-1111-1111-111111111111" >/dev/null
ccadd "Shared Two" "22222222-2222-2222-2222-222222222222" >/dev/null
out=$(ccremove -y "Shared");    okc "ccremove ambiguous refused" "ambiguous" "$out"
okc "ambiguous lists candidate 1" "Shared One" "$out"
n=$(_cc_rows | wc -l | tr -d ' '); ok "nothing removed on ambiguous" 4 "$n"

print "===== ccnote ====="
out=$(ccnote "Alpha" "brand new notes"); okc "ccnote updates" "Updated notes for 'Alpha'" "$out"
okc "note text written" "brand new notes" "$(cat "$CC_MAP")"
ok "ccnote keeps id" "$idA" "$(_cc_rows | awk -F'\t' '$1=="Alpha"{print $2}')"
out=$(ccnote "Shared" "x"); okc "ccnote ambiguous refused" "ambiguous" "$out"
out=$(ccnote "zzz" "x");    okc "ccnote no match" "No entry matching" "$out"
out=$(ccnote "Alpha" "has | pipe"); okc "ccnote pipe rejected" "cannot contain '|'" "$out"
ccnote "Alpha" >/dev/null 2>&1; okrc "ccnote usage exit" 2 $?
n=$(_cc_rows | wc -l | tr -d ' '); ok "count unchanged after ccnote" 4 "$n"

print "===== --help / -h flags ====="
out=$(ccfetch --help);  okc "ccfetch --help"  "summarise the context of another chat" "$out"
out=$(ccspec -h);       okc "ccspec -h"        "generate a SPEC document"              "$out"
out=$(cccache -h);      okc "cccache -h"       "manage the ccfetch/ccspec summary cache" "$out"
out=$(ccresume --help); okc "ccresume --help"  "resume a mapped chat by name"          "$out"
out=$(ccadd --help);    okc "ccadd --help"     "add a row to the map"                   "$out"
ccadd -h >/dev/null 2>&1;  okrc "ccadd -h short-circuits (rc 0, no side effects)" 0 $?
n=$(_cc_rows | wc -l | tr -d ' '); ok "map unchanged by ccadd -h" 4 "$n"

print "===== ccplay wordle ====="
out=$(ccplay list);                      okc "wordle in games list" "wordle" "$out"
out=$(printf 'q\n' | ccplay wordle 2>&1); okc "wordle reveals word on quit" "the word was" "$out"
stripped=$(print -r -- "$out" | perl -pe 's/\e\[[0-9;]*m//g; s/ //g')
okc "wordle shows the keyboard tracker" "QWERTYUIOP" "$stripped"
[[ -r /usr/share/dict/words ]] && { out=$(printf 'zxqwj\nq\n' | ccplay wordle 2>&1); okc "wordle rejects a non-dictionary guess" "not in the word list" "$out"; }
out=$(ccplay nope 2>&1);                 okc "unknown game rejected" "unknown game" "$out"

print "===== slash commands installed ====="
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccadd.md" ]];   okrc "/ccadd installed"   0 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccfetch.md" ]]; okrc "/ccfetch installed" 0 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccspec.md" ]];  okrc "/ccspec installed"  0 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccexplain.md" ]]; okrc "/ccexplain installed" 0 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccexport.md" ]];  okrc "/ccexport installed"  0 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccname.md" ]];    okrc "/ccname installed"    0 $?
# installer must bake the real map path in (no {MAPPORT} placeholder left behind)
okn "/ccfetch MAPPORT substituted" "{MAPPORT}" "$(cat "$CLAUDE_CONFIG_DIR/commands/ccfetch.md")"
okc "/ccfetch has real map path"   "$CC_MAP"   "$(cat "$CLAUDE_CONFIG_DIR/commands/ccfetch.md")"
okn "/ccname MAPPORT substituted"  "{MAPPORT}" "$(cat "$CLAUDE_CONFIG_DIR/commands/ccname.md")"

print "===== cchelp ====="
out=$(cchelp); okc "cchelp shows ccresume" "ccresume" "$out"; okc "cchelp shows map path" "$CC_MAP" "$out"
cchelp >/dev/null; okrc "cchelp exit 0" 0 $?

print "===== completion registration ====="
(( $+functions[_cc_complete_names] )); okrc "_cc_complete_names defined" 0 $?
comp_names=(${(f)"$(_cc_rows | cut -f1)"})
okc "completion candidates include a mapped name" "Alpha" "${comp_names[*]}"
okc "completion registered for ccresume" "ccresume" "${_CC_COMPDEF_ARGS-}"
okc "completion registered for ccfetch"  "ccfetch"  "${_CC_COMPDEF_ARGS-}"
okc "completion registered for ccnote"   "ccnote"   "${_CC_COMPDEF_ARGS-}"
okc "completion registered for ccspec"   "ccspec"   "${_CC_COMPDEF_ARGS-}"
okc "completion registered for ccfind"   "ccfind"   "${_CC_COMPDEF_ARGS-}"

print "===== prose/header still intact at the end ====="
okc "header row intact" "| Conversation name | Session ID | Notes |" "$(cat "$CC_MAP")"
okc "separator intact" "|---|---|---|" "$(cat "$CC_MAP")"

print "===== uninstall ====="
sh "$INSTALLER" --uninstall >/dev/null
[[ -f "$CLAUDE_CONFIG_DIR/claudius.zsh" ]]; okrc "helper removed" 1 $?
[[ -f "$CC_MAP" ]]; okrc "map kept" 0 $?
ok "rc source line removed" 0 "$(grep -c claudius.zsh "$SB/.zshrc")"
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccadd.md" ]];   okrc "/ccadd removed"   1 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccfetch.md" ]]; okrc "/ccfetch removed" 1 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccspec.md" ]];  okrc "/ccspec removed"  1 $?
[[ -f "$CLAUDE_CONFIG_DIR/commands/ccname.md" ]];  okrc "/ccname removed"  1 $?

rm -rf "$SB"
print "\n================  $PASS passed, $FAIL failed  ================"
[[ $FAIL -eq 0 ]]
