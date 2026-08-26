---
description: Play a quick game in this chat (menu of games)
argument-hint: [wordle|guess|rps|flip|roll|math|hangman|scramble|8ball]
---
Play a quick, light game with me right here in the chat — a break while something else runs.

Note: this runs in the current conversation, so it DOES use this chat's context/tokens. For a zero-impact game (and a couple of extras like a reaction-timer), run `ccplay` in a separate terminal instead.

**If `$ARGUMENTS` is empty**, show this exact menu and ask me to pick a number or name (then wait):

```
🎮 Pick a game
  1) wordle   — Guess a 5-letter word in 6 tries (🟩🟨⬛ feedback)
  2) guess    — Hi-Lo: guess a hidden number 1–100
  3) rps      — Rock–paper–scissors
  4) flip     — Coin flip
  5) roll     — Roll two dice
  6) math     — Quick arithmetic quiz (5 questions)
  7) hangman  — Guess the word letter by letter
  8) scramble — Unscramble a jumbled word
  9) 8ball    — Ask a yes/no question
```

**Once a game is chosen** (from the menu or from `$ARGUMENTS`), first print its one-line instructions, then start:

- **wordle** — "Guess a 5-letter word in 6 tries; I'll mark each letter 🟩 right spot / 🟨 in word, wrong spot / ⬛ not in word." Pick a secret common 5-letter word and keep it hidden in your reasoning. For each guess: reject anything that isn't 5 letters, and reject guesses that are **not real English words** (ask for a real word — don't score gibberish). Otherwise render one row of 5 emoji tiles (🟩/🟨/⬛) followed by the guess in caps, using correct duplicate-letter rules (mark greens first, then yellows only while unused copies of that letter remain, else ⬛). Show all past guess rows each turn, and **below them show a QWERTY keyboard tracker** with each letter marked by its best status so far (🟩/🟨 or ⬛ for used-and-absent, plain if unused) so I can see which letters are still available. Win on an exact match (celebrate with the try count); after 6 wrong guesses, reveal the word. Never reveal it early.
- **guess** — "I've picked a number 1–100; guess and I'll say higher/lower." Pick a secret whole number, keep it hidden in your reasoning, respond only higher/lower to each guess, count tries, celebrate on success. Never reveal it early.
- **rps** — "Type rock/paper/scissors (r/p/s)." You choose secretly (vary it), announce both picks and the winner.
- **flip** — "Heads or tails?" Then flip and report.
- **roll** — "Rolling two dice." Then report both dice and the total.
- **math** — "5 quick questions — type each answer." Ask five one-line arithmetic questions (+, −, ×, single/double-digit) one at a time, mark each right/wrong, tally a final score.
- **hangman** — "Guess the word one letter at a time; 7 misses allowed." Pick a secret common word, show it as underscores, reveal matched letters, track wrong guesses, win on full reveal or lose at 7 misses. Never reveal early.
- **scramble** — "Unscramble the word." Pick a word, show its letters shuffled, check my answer.
- **8ball** — "Ask a yes/no question." Reply with a classic Magic 8-Ball answer.

Keep every message short and playful. One turn per reply, then wait for me.
