#!/bin/sh
# ============================================================================
#  Claudius installer — manage Claude Code conversations by name
#  https://github.com/SaxenaKartik/claudius
# ----------------------------------------------------------------------------
#  Works two ways:
#    • from a clone / tarball:   sh install.sh
#    • bootstrap over the web:   curl -fsSL https://raw.githubusercontent.com/SaxenaKartik/claudius/main/install.sh | sh
#
#  Options (env vars):
#    CLAUDE_CONFIG_DIR   default: ~/.claude
#    CC_MAP              default: $CLAUDE_CONFIG_DIR/cc_map.md
#    CLAUDIUS_REPO       default: SaxenaKartik/claudius        (for web bootstrap)
#    CLAUDIUS_REF        default: main
#    CLAUDIUS_NO_WARM=1  skip building the search cards in the background after install
#
#  Requires: zsh (the helpers are zsh); Claude Code on PATH as `claude`.
#  Uninstall:  sh install.sh --uninstall
# ============================================================================
set -eu

REPO="${CLAUDIUS_REPO:-SaxenaKartik/claudius}"
REF="${CLAUDIUS_REF:-main}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HELPER="$CLAUDE_DIR/claudius.zsh"
CMD_DIR="$CLAUDE_DIR/commands"
MAP="${CC_MAP:-$CLAUDE_DIR/cc_map.md}"
RC="${ZDOTDIR:-$HOME}/.zshrc"
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CMDS="ccadd ccname ccrename ccfetch ccspec ccexplain ccexport ccplay ccask ccmusic"

say() { printf '%s\n' "$*"; }

# --- uninstall --------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  # restore the previous Claude status line (if Claudius wired it) before the helper goes away
  [ -f "$HELPER" ] && command -v zsh >/dev/null 2>&1 && zsh -c "source \"$HELPER\" && ccstatus --uninstall" >/dev/null 2>&1 || true
  # restore the chat-retention limit Claudius raised (Claude Code's default is 30 days)
  [ -f "$HELPER" ] && command -v zsh >/dev/null 2>&1 && zsh -c "source \"$HELPER\" && ccretention --uninstall" >/dev/null 2>&1 || true
  rm -f "$CLAUDE_DIR/claudius-statusline-off"
  rm -f "$CLAUDE_DIR/claudius-retention-off"
  rm -f "$HELPER"
  for c in $CMDS; do rm -f "$CMD_DIR/$c.md"; done
  if [ -f "$RC" ] && grep -q "claudius.zsh" "$RC" 2>/dev/null; then
    grep -v "claudius.zsh" "$RC" > "$RC.claudius.tmp" || true
    mv "$RC.claudius.tmp" "$RC"
  fi
  say "Uninstalled Claudius (helper + slash commands + rc line). Left your map: $MAP"
  say "Reload:  source \"$RC\""
  exit 0
fi

# --- preflight --------------------------------------------------------------
command -v zsh >/dev/null 2>&1 || say "NOTE: zsh not found — Claudius helpers require zsh."
command -v claude >/dev/null 2>&1 || say "NOTE: 'claude' not found on PATH — install Claude Code first."

mkdir -p "$CLAUDE_DIR" "$CMD_DIR"
map_dir="$(dirname -- "$MAP")"; mkdir -p "$map_dir"

# fetch <relative-path> <dest> : copy from clone if present, else download
fetch() {
  _rel="$1"; _dest="$2"
  if [ -f "$SRC/$_rel" ]; then
    cp "$SRC/$_rel" "$_dest"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW/$_rel" -o "$_dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_dest" "$RAW/$_rel"
  else
    say "ERROR: need the file locally, or curl/wget to download: $_rel"; exit 1
  fi
}

# --- install helper + commands ---------------------------------------------
fetch "claudius.zsh" "$HELPER"
for c in $CMDS; do
  fetch "commands/$c.md" "$CMD_DIR/$c.md"
  # bake the real map path into the slash command (repo ships a {MAPPORT} placeholder)
  if grep -q '{MAPPORT}' "$CMD_DIR/$c.md" 2>/dev/null; then
    sed "s|{MAPPORT}|$MAP|g" "$CMD_DIR/$c.md" > "$CMD_DIR/$c.md.tmp" && mv "$CMD_DIR/$c.md.tmp" "$CMD_DIR/$c.md"
  fi
done

# --- starter map (never clobber existing) ----------------------------------
if [ ! -f "$MAP" ]; then
  cat > "$MAP" <<'MAP_EOF'
# Claude Conversation Map

Managed by Claudius (`cclist` / `ccresume` / `ccadd` / `ccname` / …).
Add rows with `ccadd "<name>"` (in a session) or `/ccadd <name>`.

| Conversation name | Session ID | Notes |
|---|---|---|

Row format: `| <Name> | `<session-id>` | notes |`
MAP_EOF
fi

# --- hook ~/.zshrc (idempotent) --------------------------------------------
LINE="source \"$HELPER\""
if [ -f "$RC" ] && grep -q "claudius.zsh" "$RC" 2>/dev/null; then
  say "rc already sources Claudius: $RC"
else
  printf '%s\n' "$LINE" >> "$RC"
  say "added to $RC: $LINE"
fi

WARM=""   # build the search cards once, in the background, so the first ccask doesn't wait (opt out: CLAUDIUS_NO_WARM=1)
command -v zsh >/dev/null 2>&1 && zsh -c "source \"$HELPER\" && _cc_warm_autostart now" >/dev/null 2>&1 && WARM=1

say ""
say "Claudius installed."
say "  helper  : $HELPER"
say "  commands: $CMD_DIR/{$(echo "$CMDS" | tr ' ' ',')}.md   (use /ccadd /ccname /ccrename /ccfetch /ccask /ccspec /ccexplain /ccexport /ccplay /ccmusic in a chat)"
say "  map     : $MAP"
[ -n "$WARM" ] && say "  cards   : building search cards for your chats in the background (one-time, one Claude call per chat; log: $CLAUDE_DIR/claudius-cache/warm.log) — opt out: CLAUDIUS_NO_WARM=1"
say "  chats   : kept 1 year after last use (Claude Code's default is 30 days) — on first load; opt out: CLAUDIUS_NO_RETENTION=1"
say ""
say "Reload now:  source \"$RC\"     then run:  claudius  (walkthrough)  ·  cchelp  (all commands)"
