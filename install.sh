#!/usr/bin/env bash
set -e

SRC="$(cd "$(dirname "$0")" && pwd)/flathub-manager.sh"
DEST="$HOME/.local/bin/flathub-manager.sh"

mkdir -p "$HOME/.local/bin"
cp "$SRC" "$DEST"
chmod +x "$DEST"

echo "Installed to: $DEST"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo
    echo "Warning: ~/.local/bin is not in PATH."
    echo "Add this line to your shell config if needed:"
    echo 'export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac
