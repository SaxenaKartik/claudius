#!/bin/sh
# ============================================================================
#  Claudius installer — manage Claude Code conversations by name
#  https://github.com/OWNER/claudius
# ----------------------------------------------------------------------------
#  Works two ways:
#    • from a clone / tarball:   sh install.sh
#    • bootstrap over the web:   curl -fsSL https://raw.githubusercontent.com/OWNER/claudius/main/install.sh | sh
#
#  Options (env vars):
#    CLAUDE_CONFIG_DIR   default: ~/.claude
#    CC_MAP              default: $CLAUDE_CONFIG_DIR/cc_map.md
#    CLAUDIUS_REPO       default: OWNER/claudius        (for web bootstrap)
#    CLAUDIUS_REF        default: main
#
#  Requires: zsh (the helpers are zsh); Claude Code on PATH as `claude`.
#  Uninstall:  sh install.sh --uninstall
# ============================================================================
set -eu

REPO="${CLAUDIUS_REPO:-OWNER/claudius}"
REF="${CLAUDIUS_REF:-main}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HELPER="$CLAUDE_DIR/claudius.zsh"
CMD_DIR="$CLAUDE_DIR/commands"
MAP="${CC_MAP:-$CLAUDE_DIR/cc_map.md}"
RC="${ZDOTDIR:-$HOME}/.zshrc"
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CMDS="ccadd ccname ccfetch ccspec ccexplain ccexport ccplay"

say() { printf '%s\n' "$*"; }

# --- uninstall --------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
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
for c in $CMDS; do fetch "commands/$c.md" "$CMD_DIR/$c.md"; done

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

say ""
say "Claudius installed."
say "  helper  : $HELPER"
say "  commands: $CMD_DIR/{$(echo "$CMDS" | tr ' ' ',')}.md   (use /ccadd /ccname /ccfetch /ccspec /ccexplain /ccexport in a chat)"
say "  map     : $MAP"
say ""
say "Reload now:  source \"$RC\"     then run:  cchelp"
