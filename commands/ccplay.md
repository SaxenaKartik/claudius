---
description: Play a quick game in this chat (menu of games)
argument-hint: [guess|rps|flip|roll|math|hangman|scramble|8ball]
---
Play a quick, light game with me right here in the chat — a break while something else runs.

Note: this runs in the current conversation, so it DOES use this chat's context/tokens. For a zero-impact game (and a couple of extras like a reaction-timer), run `ccplay` in a separate terminal instead.

**If `$ARGUMENTS` is empty**, show this exact menu and ask me to pick a number or name (then wait):

```
🎮 Pick a game
  1) guess    — Hi-Lo: guess a hidden number 1–100
  2) rps      — Rock–paper–scissors
  3) flip     — Coin flip
  4) roll     — Roll two dice
  5) math     — Quick arithmetic quiz (5 questions)
  6) hangman  — Guess the word letter by letter
  7) scramble — Unscramble a jumbled word
  8) 8ball    — Ask a yes/no question
```

**Once a game is chosen** (from the menu or from `$ARGUMENTS`), first print its one-line instructions, then start:

- **guess** — "I've picked a number 1–100; guess and I'll say higher/lower." Pick a secret whole number, keep it hidden in your reasoning, respond only higher/lower to each guess, count tries, celebrate on success. Never reveal it early.
- **rps** — "Type rock/paper/scissors (r/p/s)." You choose secretly (vary it), announce both picks and the winner.
- **flip** — "Heads or tails?" Then flip and report.
- **roll** — "Rolling two dice." Then report both dice and the total.
- **math** — "5 quick questions — type each answer." Ask five one-line arithmetic questions (+, −, ×, single/double-digit) one at a time, mark each right/wrong, tally a final score.
- **hangman** — "Guess the word one letter at a time; 7 misses allowed." Pick a secret common word, show it as underscores, reveal matched letters, track wrong guesses, win on full reveal or lose at 7 misses. Never reveal early.
- **scramble** — "Unscramble the word." Pick a word, show its letters shuffled, check my answer.
- **8ball** — "Ask a yes/no question." Reply with a classic Magic 8-Ball answer.

Keep every message short and playful. One turn per reply, then wait for me.
