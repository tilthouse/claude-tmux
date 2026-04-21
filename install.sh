#!/usr/bin/env bash
# install.sh — symlink claude-tmux, cct, ccg, and sesh-pick into ~/.local/bin.
#
# This is for local-repo development. For normal end-user install, use:
#     gem install claude-tmux
#
# Pre-existing regular files at destinations are renamed to .bak before linking;
# existing symlinks are replaced without backup.

set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

link() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "Already linked: $dest"
    return
  fi
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

for name in claude-tmux cct ccg ccs; do
  link "$REPO/bin/$name" "$BIN/$name"
done

# v0.3 migration: remove any leftover sesh-pick symlink from previous installs.
if [ -L "$BIN/sesh-pick" ]; then
  rm "$BIN/sesh-pick"
  echo "Removed legacy symlink $BIN/sesh-pick (renamed to ccs)"
fi

echo
echo "Ensure $BIN is on your PATH."
echo "Runtime deps (Homebrew): brew install tmux sesh fzf zoxide"
echo "Requires Ruby >= 3.0 (asdf, rbenv, or system)."
