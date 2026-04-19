#!/usr/bin/env bash
# install.sh — symlink claude-tmux, sesh-pick, and cct into ~/.local/bin.
# Pre-existing regular files at destinations are renamed to .bak before linking.
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

link() {
  local src="$1" dest="$2"
  # Already correctly linked? No-op (idempotent re-run).
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "Already linked: $dest"
    return
  fi
  # Regular file — preserve with .bak. Refuse to overwrite an existing .bak.
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    if [ -e "$dest.bak" ]; then
      echo "ERROR: $dest is a regular file and $dest.bak already exists." >&2
      echo "       Resolve manually (move/remove one) and re-run." >&2
      return 1
    fi
    mv "$dest" "$dest.bak"
    echo "Backed up $dest → $dest.bak"
  elif [ -L "$dest" ]; then
    rm "$dest"
  fi
  ln -s "$src" "$dest"
  echo "Linked $dest → $src"
}

link "$REPO/bin/claude-tmux" "$BIN/claude-tmux"
link "$REPO/bin/sesh-pick"   "$BIN/sesh-pick"
link "$BIN/claude-tmux"      "$BIN/cct"

echo
echo "Ensure $BIN is on your PATH."
echo "Deps (Homebrew): brew install tmux sesh fzf zoxide"
