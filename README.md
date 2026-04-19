# claude-tmux

Per-project tmux session launcher for [Claude Code](https://claude.com/claude-code), with preset flag bundles and a state-aware session picker.

## What it does

- **Per-project sessions.** Derives a stable session name from the git root (or a `.cct-name` override), attaches if the session exists, creates it otherwise. Running `cct` from anywhere inside a repo lands you in the same session.
- **Preset flag bundles.** Short aliases for common flag combinations: `plan`, `yolo`, `sonnet`, `opus`, `auto`, `accept`.
- **Remote Control with timestamped sessions.** The `rc` modifier launches Claude with `--remote-control` and appends a timestamp to the session name so repeated RC sessions don't collide.
- **Decorated session picker (`sesh-pick`).** Wraps [sesh](https://github.com/joshmedeski/sesh) with per-session Claude state glyphs: `●` active, `◐` awaiting input, `○` idle, `·` configured-but-not-running.

## Requirements

- [tmux](https://github.com/tmux/tmux) 3.x
- [Claude Code](https://claude.com/claude-code) on `PATH` as `claude`
- For `sesh-pick`: [sesh](https://github.com/joshmedeski/sesh), [fzf](https://github.com/junegunn/fzf); [zoxide](https://github.com/ajeetdsouza/zoxide) recommended

Homebrew:

```bash
brew install tmux sesh fzf zoxide
```

## Install

```bash
git clone https://github.com/<you>/claude-tmux ~/Developer/tools/claude-tmux
~/Developer/tools/claude-tmux/install.sh
```

The installer symlinks `claude-tmux`, `sesh-pick`, and `cct` (a convenience alias-as-symlink for `claude-tmux`) into `~/.local/bin/`. Ensure that's on your `PATH`.

## Usage

```
cct --help
```

### Common patterns

```bash
cct                           # Default session for current project
cct plan                      # Plan mode
cct yolo                      # Skip all permission prompts
cct rc                        # Remote Control, timestamped session
cct rc plan                   # Remote Control + plan mode
cct -n scratch                # Override session name: cc-scratch
cct -- --add-dir ../sibling   # Pass extra flags through to claude
```

### Session naming precedence

1. `-n <name>` command-line flag → `cc-<name>`
2. `.cct-name` file at git root → `cc-<file contents>`
3. `git rev-parse --show-toplevel` basename → `cc-<basename>`
4. Current directory basename (no git repo) → `cc-<basename>`

With `rc`, a `-YYYYMMDD-HHMMSS` suffix is appended in all cases.

### Tmux keybinding for the decorated picker

Add to your `~/.tmux.conf`:

```
bind-key s display-popup -E -w 60% -h 70% "sesh-pick"
bind-key S choose-tree -Zs
```

This swaps tmux's default `prefix+s` (choose-tree) onto uppercase `S` and puts the decorated picker on the ergonomic lowercase binding.

## How the picker glyphs work

`sesh-pick` runs `tmux capture-pane` on each session and pattern-matches the output:

- `●` active — pane contains `"esc to interrupt"` (Claude is running a tool call)
- `◐` awaiting input — pane contains `"Do you want"` or numbered-option prompt markers
- `○` idle — a Claude session that isn't in either state above (or a non-Claude session)
- `·` configured but no tmux session is running under that name

Patterns live at the top of `bin/sesh-pick`; if Claude Code rewords any prompt strings, update them there.

## License

MIT — see [LICENSE](LICENSE).
