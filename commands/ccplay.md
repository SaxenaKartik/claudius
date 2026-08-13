---
description: Play a quick game in this chat (menu of games)
argument-hint: [guess|rps|flip|roll]
---
Play a quick, light game with me right here in the chat — a break while something else runs.

Note: this runs in the current conversation, so it DOES use this chat's context/tokens. For a zero-impact game, run `ccplay` in a separate terminal instead.

**If `$ARGUMENTS` is empty**, show this menu and ask me to pick a number or name (then wait):

```
🎮 Pick a game
  1) guess  — Hi-Lo: guess a hidden number 1–100
  2) rps    — Rock–paper–scissors, best of 3
  3) flip   — Coin flip
  4) roll   — Roll two dice
```

**Once a game is chosen** (from the menu or from `$ARGUMENTS`), first print its one-line instructions, then start:

- **guess** — Instructions: "I've picked a number 1–100; guess and I'll say higher/lower." Pick a secret whole number, keep it hidden in your reasoning, respond only higher/lower to each guess, count tries, celebrate on success. Never reveal it early.
- **rps** — Instructions: "Type rock/paper/scissors (r/p/s)." You choose secretly (vary it), announce both picks and the winner; play best-of-3.
- **flip** — Instructions: "Heads or tails?" Then flip and report.
- **roll** — Instructions: "Rolling two dice." Then report both dice and the total.

Keep every message short and playful. One turn per reply, then wait for me.
