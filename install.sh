#!/usr/bin/env bash
# Installs the status line script into ~/.claude/statusline/ and makes sure
# jq is available. Does NOT touch settings.json — see README.md for the
# exact snippet to add (kept manual on purpose, so it never clobbers your
# other Claude Code settings).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.claude/statusline"
DEST_FILE="$DEST_DIR/claude-code-statusline.sh"

mkdir -p "$DEST_DIR"
cp "$SRC_DIR/statusline.sh" "$DEST_FILE"
chmod +x "$DEST_FILE"
echo "Installed: $DEST_FILE"

if command -v jq &>/dev/null; then
  echo "jq found: $(command -v jq)"
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      echo "jq not found — downloading a static jq.exe for Windows..."
      mkdir -p "$HOME/bin"
      if command -v curl &>/dev/null; then
        curl -fsSL -o "$HOME/bin/jq.exe" \
          https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
      else
        echo "curl not found — download jq manually from https://jqlang.org/download/ and place it at $HOME/bin/jq.exe" >&2
        exit 1
      fi
      chmod +x "$HOME/bin/jq.exe"
      echo "Installed: $HOME/bin/jq.exe (the script auto-detects this path even if it's not on your Windows PATH)"
      ;;
    *)
      echo "jq not found. Install it with your package manager, e.g.:" >&2
      echo "  macOS:   brew install jq" >&2
      echo "  Debian:  sudo apt install jq" >&2
      exit 1
      ;;
  esac
fi

echo ""
echo "Next: add the statusLine block from README.md to ~/.claude/settings.json, then restart Claude Code."
