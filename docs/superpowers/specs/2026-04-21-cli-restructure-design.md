# CLI Restructure + Cascading Dotfile Defaults (v0.3.0)

## Context

The current CLI has two "radically different" shapes:

- `cct` uses bareword positional presets (`cct plan sonnet`) with flag options mixed in.
- `ccg` stacks bareword disambiguation (preset vs. pathlike vs. group-name) with first-positional subcommands (`add|rm|list|edit`).
- `sesh-pick` is its own thing.

This is hard to document, hard to extend, and forces the parsers to carry special rules for bareword categorization. Separately, the user wants a way to set default options (session name, permission mode, model, `--rc`, etc.) per project via a dotfile that **cascades from `$HOME` down to `$PWD`**, so org-wide, per-group, and per-repo defaults can compose.

This plan does both things together because they touch the same parsers, help text, and docs; splitting them would double the rewrite cost.

## Goals

1. Single canonical shape: `claude-tmux <subcommand> [subsub] [options] [positional...]`.
2. Two verbs: `project` (single-project attach-or-create) and `group` (multi-project dashboard). Management subcommands nest under `group` (`group add|rm|list|edit`).
3. Presets migrate to options: `-p/--permission`, `-m/--model`, `--yolo`. No more positional barewords for presets.
4. Per-project TOML dotfile `.claude-tmux.toml` and user-wide `~/.config/cct/options.toml` supply default options; cascade merges all files found walking from `$HOME` down to `$PWD`, deeper-wins.
5. `.cct-name` removed; migration note in CHANGELOG.

## Final command tree

```
claude-tmux                                         # print help
claude-tmux project  [OPTS] [DIR]                   # single-project launch
claude-tmux group    [OPTS] [GROUP|PATH]...         # group launch (bare → picker)
claude-tmux group add  <name> <path> [OPTS]         # add/update entry
claude-tmux group rm   <name> [<path>]              # remove entry/group
claude-tmux group list [<name>]                     # list
claude-tmux group edit                              # open groups.conf in $EDITOR
claude-tmux sess-pick                               # decorated sesh picker (canonical)
claude-tmux pick                                    # alias of sess-pick
```

Symlinks (dispatched by `basename $0`):

- `cct`  → `claude-tmux project`
- `ccg`  → `claude-tmux group`
- `ccs`  → `claude-tmux sess-pick`

Removed: the `cct group …` positional-subcommand alias. (Users call `ccg` or `claude-tmux group` directly.)

## Options inventory

**Shared (`project` and `group`):**

- `-n, --name <NAME>` — session basename (project) or dashboard label (group)
- `--rc` — Remote Control; timestamped RC prefix, tmux session name unchanged
- `--` — pass remaining args verbatim to `claude`
- `-h, --help`

**`project`-only:**

- `-p, --permission <MODE>` — `plan | accept | auto`
- `-m, --model <NAME>` — `opus | sonnet`
- `--yolo` — maps to claude `--dangerously-skip-permissions`
- `-c, --continue` — errors if session exists (current guard preserved)
- `-r, --resume [ID]` — errors if session exists

**`group`-only:**

- `-p`, `-m`, `--yolo` as defaults for **newly-created source sessions** (per-entry config presets still override)
- `-c`/`-r` hard-rejected (current behavior preserved)

**Positional rules:**

- `project`: 0 args → cwd; 1 `DIR` → `cd` there first, derive name from that root's chain; 2+ → error ("use `ccg` for multiple projects")
- `group`: 0 args → picker; barewords disambiguated top-down: pathlike (starts `/`, `./`, `../`, `~/`, `~`) → path; else → config group name (must exist); unknown → error with hint. **No preset branch** — those are options now.

## Dotfile defaults

### Files

1. **Per-project:** `.claude-tmux.toml` at any dir in the walk. Multiple files can exist in the same tree (e.g., `$HOME/.claude-tmux.toml`, `$HOME/Developer/.claude-tmux.toml`, `$HOME/Developer/proj/.claude-tmux.toml`); **all are merged**.
2. **User-wide:** `~/.config/cct/options.toml`. Applied as the lowest-priority baseline.

### Cascade algorithm (for `project` mode)

1. Start `cursor = Dir.pwd`.
2. Collect every `.claude-tmux.toml` found by walking upward from `cursor`, stopping when (a) the walk passes `$HOME`'s parent, or (b) `cursor == '/'`. The walk is **inclusive of `$HOME`** — a `.claude-tmux.toml` directly in `$HOME` is the top of the per-project cascade.
3. Merge the collected files shallowest-first (so each deeper file overrides); top-level keys override by key; `[project]`/`[group]` tables merge their keys.
4. Merge `~/.config/cct/options.toml` **underneath** step 3 (lowest priority among config sources).
5. Apply CLI flags **on top** (highest priority).

For `group` mode, the cascade runs relative to `Dir.pwd` (same as `project`). Per-source-project overrides inside `group` mode still come from `groups.conf` entries (per-entry preset tokens), which win over the dotfile cascade for that source; CLI flags remain highest.

### TOML schema

```toml
# Applies to both modes unless a [project]/[group] table overrides
permission = "plan"      # plan | accept | auto
model      = "sonnet"    # opus | sonnet
yolo       = false       # bool
rc         = false       # bool

[project]
name = "my-session"      # overrides derived basename (the old .cct-name role)

[group]
label = "work"           # default dashboard label for ad-hoc invocations
```

Unknown keys → warn + ignore (don't abort; forward-compat). Invalid values for enum keys → hard error with line/column from the TOML parser.

### Precedence (highest → lowest)

1. CLI flags
2. Per-entry config presets (group-mode only; in `groups.conf`)
3. `.claude-tmux.toml` cascade (deepest `$PWD`-side file wins among dotfiles)
4. `~/.config/cct/options.toml`
5. Built-in defaults

## Internal changes

### Renames

- Class `ClaudeTmux::Cct` → `ClaudeTmux::Project`.
- Files: `lib/claude_tmux/cct.rb` → `project.rb`; `lib/claude_tmux/cct/{parser,help}.rb` → `project/{parser,help}.rb`.
- Spec files: parallel renames.
- The existing `ClaudeTmux::Project` **module** (session-name utility) → rename to `ClaudeTmux::SessionName` (module) so the class can take the `Project` name.

### New module

- `lib/claude_tmux/options.rb` — `ClaudeTmux::Options` class:
  - `.load(dir: Dir.pwd, home: Dir.home)` → merged hash keyed by `:permission`, `:model`, `:yolo`, `:rc`, `:name`, `:label`.
  - Walks from `dir` up to `home` (inclusive), collects `.claude-tmux.toml` files, merges shallowest-first.
  - Merges `~/.config/cct/options.toml` as lowest-priority baseline.
  - Produces plain ruby hash — callers convert to CLI arg tokens themselves.

### Parser changes

- `lib/claude_tmux/project/parser.rb`:
  - Drop `add_preset` and `Presets::ALL` bareword branch.
  - Add `OptionParser`-driven options: `-p/--permission`, `-m/--model`, `--yolo`, existing `-n`, `-c`, `-r`, `--rc`.
  - Accept optional positional `DIR`; error on 2+ positionals.
  - On init, load `Options` and seed defaults before parsing CLI args (CLI wins).
- `lib/claude_tmux/group/parser.rb`:
  - Drop preset-bareword branch; add `-p/-m/--yolo` as default-source options.
  - Bareword classifier simplifies to pathlike vs. config-group vs. error.
  - Load `Options` for group defaults (`[group] label`).

### Dispatcher

- `lib/claude_tmux/cli.rb`:
  - Symlink map: `cct → project`, `ccg → group`, `ccs → sess-pick`.
  - First-arg-is-subcommand dispatch when invoked as `claude-tmux`: `project|group|pick|sess-pick`.
  - Remove the legacy `cct group …` consumption.

### Binaries

- Rename `bin/sesh-pick` → `bin/ccs`; add `bin/ccs` symlink target path.
- All four `bin/*` scripts remain identical five-liners; `$PROGRAM_NAME` drives dispatch.
- Update `claude-tmux.gemspec` `spec.executables` to `%w[claude-tmux cct ccg ccs]`.
- Update `install.sh` symlink list.

### Presets module

- `lib/claude_tmux/presets.rb` becomes a **value mapping only** (no bareword resolution). Keep `flags_for(permission:, model:, yolo:)` that returns the claude-flag array. Drop `ALL`, `category`, `preset?` (no longer used outside parser).

### Config (groups.conf)

- `Config::RESERVED_WORDS` list unchanged (`add`, `rm`, `list`, `edit`) — still rejected as group names.
- Entry preset tokens format unchanged for backwards compatibility with existing `groups.conf` files.

### Dependency

- Add `gem 'toml-rb', '~> 2.2'` as a runtime dep in `claude-tmux.gemspec`.

## Files touched

**Modify:**

- `lib/claude_tmux.rb` — update requires (cct → project, sess-pick addition, new options module)
- `lib/claude_tmux/cli.rb` — symlink map + subcommand dispatch
- `lib/claude_tmux/group.rb` — drop preset-bareword handling; wire Options
- `lib/claude_tmux/group/parser.rb` — simplify classifier; add `-p/-m/--yolo`
- `lib/claude_tmux/group/help.rb` — new invocation examples, option docs
- `lib/claude_tmux/picker.rb` — help text ("ccs"), no behavior change
- `lib/claude_tmux/presets.rb` — reduce to flag-mapping utilities
- `lib/claude_tmux/project.rb` (renamed from cct.rb) — load Options; drop bareword presets; accept `[DIR]`
- `lib/claude_tmux/project/parser.rb` (renamed) — OptionParser-based options
- `lib/claude_tmux/project/help.rb` (renamed) — new help
- `claude-tmux.gemspec` — deps + executables + description
- `install.sh` — updated symlink list
- `README.md` — new shape; dotfile section
- `CLAUDE.md` — new shape; dotfile section; migration notes
- `CHANGELOG.md` — v0.3.0 entry, breaking-change call-outs

**Add:**

- `lib/claude_tmux/options.rb` — TOML cascade loader
- `lib/claude_tmux/session_name.rb` (renamed from current `project.rb` module) — session-name computation utility
- `bin/ccs` — sess-pick symlink target
- `spec/claude_tmux/options_spec.rb` — cascade + merge tests
- `spec/claude_tmux/project/parser_spec.rb` — renamed from `cct/parser_spec.rb`, rewritten for option-based parsing
- `spec/claude_tmux/project_spec.rb` (class version) — renamed from `cct_spec.rb`
- Renamed: `spec/claude_tmux/project_spec.rb` → `spec/claude_tmux/session_name_spec.rb` (module tests)

**Delete:**

- `bin/sesh-pick` (replaced by `bin/ccs`)
- `lib/claude_tmux/cct.rb` and `lib/claude_tmux/cct/` (moved to project)
- All code reading `.cct-name` (removed feature)

## Testing

Unit coverage added/updated:

- `options_spec.rb`: cascade walks stop at `$HOME`; `.claude-tmux.toml` merge shallow-first; user-wide `options.toml` is lowest priority; CLI still wins; unknown-key warnings don't raise; invalid-enum values raise with context; malformed TOML surfaces the parser's line number.
- `project/parser_spec.rb`: each option flag parses correctly; mutex on `-p/-m` value set (only valid enum values accepted); positional DIR accepted once; two positionals errors; `-c`/`-r` mutex; `--` passthrough.
- `group/parser_spec.rb`: pathlike classification; group-name classification; unknown bareword errors; `-p/-m/--yolo` as group-mode defaults.
- `project_spec.rb`: dotfile-derived defaults combine with CLI flags correctly; per-project `.claude-tmux.toml` name overrides basename derivation; `-c` guard still fires on existing session.
- `cct_spec.rb` / `cct/parser_spec.rb`: deleted.

End-to-end smoke (manual; unchanged ergonomics on the installed side):

```bash
# In a fresh repo:
echo -e '[project]\nname = "foo"\n\npermission = "plan"' > .claude-tmux.toml
cct --help                      # new option vocabulary renders
cct                             # session name is cc-foo; claude started with --permission-mode plan
cct -p auto                     # CLI wins; plan overridden
ccg --help                      # new shape
ccg add morning . -p plan       # per-entry config preset in groups.conf still stored
ccg morning                     # dashboard built; new sources get --permission-mode plan (from dotfile) + per-entry override
ccs                             # sesh-pick
claude-tmux                     # prints help
claude-tmux project             # equivalent to cct
claude-tmux group list          # equivalent to ccg list
```

Automated: `bundle exec rspec` (all pass) + `bundle exec rubocop` (clean).

## Migration / release notes (v0.3.0 — breaking)

- Positional preset barewords removed. `cct plan sonnet` → `cct -p plan -m sonnet`. `cct yolo` → `cct --yolo`. `ccg morning plan` → `ccg -p plan morning`.
- `.cct-name` removed. Convert to `.claude-tmux.toml` with `[project]\nname = "..."`.
- `sesh-pick` binary renamed to `ccs`. Users who symlinked `sesh-pick` manually: update their tmux keybinding. `install.sh` handles this automatically.
- `cct group …` invocation form removed. Use `ccg` or `claude-tmux group` directly.

## Non-goals

- Merging `groups.conf` into the TOML file. Groups have per-entry structure that does not fit cleanly into a flat options schema; kept as a separate concern.
- Environment-variable defaults (`CLAUDE_TMUX_PERMISSION=plan`). Defer until/unless asked; dotfile + user-wide should cover the use cases.
- Auto-migration of `.cct-name` files on first run. Manual migration documented in CHANGELOG.
- Custom `sesh-pick` glyph for `ccg-*` dashboard sessions. Tracked as nice-to-have; behavior unchanged from today.
