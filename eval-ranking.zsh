#!/bin/zsh
# Ranking-quality eval for `ccask -a`.
#
# Checks WHERE the expected chat ranks for a set of labeled queries — a guardrail so a ranking
# tweak can be judged against a real, diverse set instead of a single anecdote.
#
# Cases are PRIVATE (your own chats) and live OUTSIDE this repo: one per line in
#   $CCASK_EVAL_CASES  (default: ~/.claude/ccask-eval.tsv)
# format:  <expected-session-id[|alt-id...]> <TAB> <query>
# lines beginning with # are ignored. Requires your real chat history on disk.
#
# Uses the CCASK_DEBUG_RANK hook (prints "rank<TAB>session-id", no model call) and disables
# synonym expansion, so it is deterministic and free. Exits non-zero if top-3 drops below the
# baseline ($CCASK_EVAL_MIN_TOP3, default 7) — wire it into a pre-commit check if you like.
emulate -L zsh
setopt nullglob extendedglob bare_glob_qual 2>/dev/null
compdef() { :; } 2>/dev/null

SRC=${CCASK_SRC:-${0:A:h}/claudius.zsh}
source "$SRC" 2>/dev/null || { print -u2 "eval: cannot source $SRC"; exit 2; }

CASES=${CCASK_EVAL_CASES:-$HOME/.claude/ccask-eval.tsv}
[[ -f $CASES ]] || { print -u2 "eval: no cases at $CASES (set CCASK_EVAL_CASES). Nothing to check."; exit 0; }

integer n=0 t1=0 t3=0
local exp q out rr id e rank top1
while IFS=$'\t' read -r exp q; do
  [[ -z $q || $exp == \#* ]] && continue
  (( n++ )); rank=0; top1=
  out=$(CCASK_DEBUG_RANK=1 CCASK_EXPAND=0 ccask -a "$q" 2>/dev/null)
  while IFS=$'\t' read -r rr id; do
    [[ $rr == 1 ]] && top1=${id[1,8]}
    for e in ${(s:|:)exp}; do [[ $id == ${e}* ]] && { rank=$rr; break 2; }; done
  done <<< "$out"
  (( rank == 1 )) && (( t1++ )); (( rank >= 1 && rank <= 3 )) && (( t3++ ))
  printf '%-2d rank=%-2s  exp=%-24s top1=%-10s | %s\n' $n "$rank" "$exp" "$top1" "${q[1,48]}"
done < $CASES

printf '\nTOP-1: %d/%d   TOP-3: %d/%d\n' $t1 $n $t3 $n
integer min=${CCASK_EVAL_MIN_TOP3:-7}
(( t3 >= min )) || { print -u2 "REGRESSION: top-3 $t3 < baseline $min"; exit 1; }
print "OK (top-3 $t3 >= baseline $min)"
