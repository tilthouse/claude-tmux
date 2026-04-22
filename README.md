# claude-tmux

Per-project tmux session launcher for [Claude Code](https://claude.com/claude-code),
with a group mode for multi-project workspaces, a state-aware session picker,
and cascading per-project default options.

One canonical binary, three shortcuts:

```
claude-tmux <subcommand> [options] [positional]

cct  =  claude-tmux project      # single-project attach-or-create
ccg  =  claude-tmux group        # multi-project dashboard + group management
ccs  =  claude-tmux sess-pick    # decorated sesh picker (alias: pick)
```

## Requirements

- [tmux](https://github.com/tmux/tmux) 3.x
- [Claude Code](https://claude.com/claude-code) on `PATH` as `claude`
- Ruby ≥ 3.0 (asdf, rbenv, or system Ruby)
- For `ccs` and `ccg`'s interactive picker: [sesh](https://github.com/joshmedeski/sesh) + [fzf](https://github.com/junegunn/fzf); [zoxide](https://github.com/ajeetdsouza/zoxide) recommended.

```bash
brew install tmux sesh fzf zoxide
```

## Install

### From RubyGems (recommended)

```bash
gem install claude-tmux
```

Then put `$GEM_HOME/bin` on your `PATH`.

### From source (local symlinks)

```bash
git clone https://github.com/tilthouse/claude-tmux ~/Developer/tools/claude-tmux
~/Developer/tools/claude-tmux/install.sh
```

`install.sh` symlinks `claude-tmux`, `cct`, `ccg`, and `ccs` into `~/.local/bin/`.

## `cct` — per-project launcher

```
cct                              # attach-or-create cc-<cwd-project>
cct -p plan                      # plan mode
cct --yolo                       # skip all permission prompts
cct -p plan -m sonnet            # plan mode + Sonnet
cct --rc                         # Remote Control (timestamped prefix)
cct -c                           # continue latest conversation
cct -r [ID]                      # resume specific conversation / picker
cct -n scratch                   # one-off session: cc-scratch
cct ~/Developer/foo              # launch in a different dir
cct -- --add-dir ../sibling      # passthrough to claude
```

**Options:** `-p/--permission {plan|accept|auto}`, `-m/--model {opus|sonnet}`,
`--yolo`, `--rc`, `-n/--name`, `-c/--continue`, `-r/--resume [ID]`.

**Session naming precedence (highest → lowest):**

1. `-n NAME`
2. `[project] name` from the cascading options cascade (see below)
3. `<git-root>` basename of `DIR` or `$PWD`
4. basename of `DIR` or `$PWD` (no git repo)

Always prefixed with `cc-`. Modifiers (`--rc`, `-c`, `-r`) never change the
tmux session name — rerunning `cct` in the same project attaches. With
`--rc`, a `-YY-MM-DD-HHMM` timestamp is passed to claude as the RC prefix
(so the mobile picker distinguishes invocations), but the tmux name is
unchanged.

`-c` and `-r` error out if the target session is already running
(they create a new claude with those flags; they can't apply to an
already-running process). Kill the session first, or use `-n <name>`
for a concurrent session.

## `ccg` — group mode

One tmux window per project inside a grouping session (`ccg-<label>`).
Per-project source sessions stay `cc-<project>` so they remain reachable
via `cct` in their repos.

```
ccg                              # interactive picker
ccg morning                      # launch a named group from config
ccg ~/Developer/a ~/Developer/b  # ad-hoc list of paths
ccg morning ~/Developer/extra    # named group + extras
ccg morning evening              # union of multiple groups
ccg -p plan -m sonnet morning    # default flags for newly-created sources
ccg --rc morning                 # RC on newly-created sources (shared timestamp)
ccg -n work morning              # override grouping-session label: ccg-work
```

`-c` and `-r` are rejected in group mode (each project's conversation is
independent).

### Group management

```
ccg add    <group> <path> [OPTIONS]   # add/update entry (. for $PWD)
ccg rm     <group> <path>             # remove one entry
ccg rm     <group>                    # delete the whole group
ccg list                              # list groups with counts
ccg list   <group>                    # dump one group's entries
ccg edit                              # open groups.conf in $EDITOR
ccg config                            # interactive TUI for managing groups
```

`add` accepts the same `-p`, `-m`, `--yolo` options as launch — they're
stored inline with the entry in `groups.conf`.

Subcommands resolve by unique prefix: `ccg c` → `config`, `ccg l` → `list`,
etc. Ambiguous prefixes error with the candidate list.

### Interactive editing — `ccg config`

`ccg config` opens an fzf-driven TUI for managing groups without
hand-editing the file. Browse groups, create / rename / delete groups,
add / remove / reorder entries, and edit per-entry presets. Hotkeys
inside a group view: `R` rename, `D` delete (with confirm). All changes
stage in memory; you'll be prompted to save on exit.

Add-entry suggestions are aggregated from existing entries in other
groups, your `sesh list` history, and a walk of `~/Developer` for
`.git`-bearing repos — deduped by canonical path. You can also type
an arbitrary path (must start with `/` or `~/`).

`ccg edit` is unchanged — it still opens `groups.conf` in `$EDITOR`.

### Config — `~/.config/cct/groups.conf`

INI-ish, one path per line, optional trailing preset tokens per entry:

```
[morning]
~/Developer/projA
~/Developer/projB plan
~/Developer/projC plan sonnet

[evening]
~/Developer/projD
```

## Default options via TOML dotfiles

Any CLI option can be preset via a TOML config file. Two locations:

- **Per-project:** `.claude-tmux.toml` at any directory in the ancestor
  walk from `$PWD` up to (and including) `$HOME`. Multiple files can
  exist in the same tree; they are merged with deeper dirs winning.
- **User-wide:** `~/.config/cct/options.toml`, applied as the lowest-priority
  baseline beneath the cascade.

```toml
# .claude-tmux.toml or ~/.config/cct/options.toml

permission = "plan"      # plan | accept | auto
model      = "sonnet"    # opus | sonnet
yolo       = false
rc         = false

[project]
name = "my-session"      # overrides session basename (used by cct)

[group]
label = "work"           # overrides grouping-session label (used by ccg)
```

**Precedence (highest → lowest):**

1. CLI flags
2. Per-entry presets in `groups.conf` (group mode only)
3. `.claude-tmux.toml` cascade (deepest ancestor wins)
4. `~/.config/cct/options.toml` (user-wide baseline)
5. Built-in defaults

Unknown keys are logged to stderr and ignored (forward-compatible).
Invalid enum values and malformed TOML raise a parse error with the
file path and line/column.

## `ccs` — decorated sesh picker

Wraps `sesh list | fzf | sesh connect` and prepends a per-session glyph
derived from `tmux capture-pane`:

- `●` active — pane contains `"esc to interrupt"` (Claude is running a tool call)
- `◐` awaiting input — pane contains `"Do you want"` or a numbered-option prompt
- `○` idle
- `·` configured but no tmux session is running

Patterns live in `lib/claude_tmux/picker.rb`; if Claude Code rewords a
prompt and a glyph stops updating, that's the first place to look.

### Tmux keybinding

```
bind-key s display-popup -E -w 60% -h 70% "ccs"
bind-key S choose-tree -Zs
```

## Development

```bash
bundle install
bundle exec rspec       # unit tests
bundle exec rubocop     # style
```

Local bin scripts resolve `lib/` via `File.realpath(__FILE__)` and
auto-load Bundler when run from this repo, so editing `bin/` or `lib/`
takes effect on the next invocation — no `gem install` needed.

## License

MIT — see [LICENSE](LICENSE).
