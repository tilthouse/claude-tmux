# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

Ruby gem shipping four binaries (`claude-tmux`, `cct`, `ccg`, `ccs`) that
launch and manage tmux sessions running Claude Code. `claude-tmux` is
the canonical long form; the three shortcuts dispatch by `$0` to the
same subcommand handlers. User-facing docs live in `README.md`; the
`--help` heredocs inside `lib/claude_tmux/*/help.rb` and
`lib/claude_tmux/cli.rb#top_level_help` are the subcommand-specific
references — keep both in sync when behavior changes.

## Commands

```bash
bundle install                       # one-time setup
bundle exec rspec                    # run tests
bundle exec rspec path/to/spec.rb    # single spec file
bundle exec rubocop                  # style
bundle exec rubocop --autocorrect    # apply autocorrections
bundle exec rake build               # pkg/claude-tmux-<version>.gem
./install.sh                         # refresh ~/.local/bin symlinks (idempotent)
```

Manual smoke-test shape: `cct --help`, `ccg --help`, `claude-tmux`,
`claude-tmux project`, `claude-tmux group list`,
`HOME=/tmp/x ccg add g /tmp/x/proj`, `cct -c` against an existing
session (guard fires), `ccg config` (TUI; ESC out is enough). Also
exercise prefix matching: `ccg c` (resolves to `config`), `ccg l`
(resolves to `list`).

Installed paths under `~/.local/bin/` are symlinks into this repo, so
edits under `bin/` and `lib/` take effect on the next invocation. Don't
edit the installed symlinks; edit the files here.

## Architecture

### Two dispatch layers

`bin/*` scripts are identical stubs that auto-load Bundler when run
from this repo (so `toml-rb` resolves without a `gem install`), then
hand off to `ClaudeTmux::CLI.new($PROGRAM_NAME, ARGV).run`.

`ClaudeTmux::CLI#dispatch` routes in two steps:

1. **Symlink name map** (`SYMLINK_MAP`): if `basename $0` is one of
   `cct`/`ccg`/`ccs`, route directly to the corresponding handler.
2. **Subcommand map** (`SUBCOMMANDS`): if invoked as `claude-tmux`,
   the first positional (`project|group|pick|sess-pick`) selects the
   handler, resolved through `PrefixResolver` so unique prefixes work
   (`claude-tmux pi` → `pick`). `pick` and `sess-pick` are aliases —
   `ccs` expands to `sess-pick` so the mnemonic is visible in help text.

Bare `claude-tmux` (or with `-h`) prints `CLI#top_level_help`.

`PrefixResolver` (`lib/claude_tmux/prefix_resolver.rb`) is reused by
`Group#run` for its own subcommand layer (`add|rm|list|edit|config`).
Exact match wins; ambiguous prefix raises `UsageError` with the
candidate list.

### Two session namespaces

- `cc-<basename>` — per-project source session created by `cct` or by
  `ccg` on demand. Glyph-decorated by `ccs`.
- `ccg-<label>`   — grouping (dashboard) session. Contains linked
  windows pointing at `cc-*` sources. Killing it does not kill sources.

`ccs`'s glyph logic keys on `cc-*` — `ccg-*` dashboards aren't
decorated. Acceptable by current design; add a `ccg-*` branch to
`Picker#status_for` if that starts to feel wrong.

### `Project` class (`lib/claude_tmux/project.rb` + `project/parser.rb`, `help.rb`)

- Parser is OptionParser-based. `-p/--permission`, `-m/--model`,
  `--yolo`, `-n/--name`, `-c/-r`, `--rc`. Positional is an **optional
  single DIR**; two or more positionals error out (suggests `ccg`).
- Flow: parse CLI → resolve DIR → load `Options` cascade → merge
  CLI-over-defaults → compute session name → guard `-c`/`-r` → launch.
- RC timestamp is computed only inside `Cct#build_claude_flags` when
  `--rc` is true and is attached to `--remote-control-session-name-prefix`,
  never to the tmux name.
- `-c`/`-r` with an existing session → `UsageError` (exit 1) rather
  than silent re-attach.

### `Group` class (`lib/claude_tmux/group.rb` + `group/*.rb`)

- Management subcommands (`add|rm|list|edit|config`) are keyed on the
  **first positional only**, resolved through `PrefixResolver` (so
  `ccg c` → `config`, etc.). Listed in `Group::RESERVED_SUBCOMMANDS`
  and rejected as config group names by `Config::RESERVED_WORDS` —
  two lists, kept in sync so each layer validates independently.
- `cmd_config` enters `ConfigTui` (`lib/claude_tmux/group/config_tui.rb`),
  a screen-pushdown loop driven by an injectable `Prompt` abstraction
  (`lib/claude_tmux/prompt.rb`), with `FakePrompt` for tests. Mutations
  stage in memory; the user is prompted to save/discard on exit.
  Add-entry candidates come from `CandidateBuilder` (other groups +
  `sesh list` + `~/Developer` walk, deduped first-seen-wins).
- `Parser` (launch path) classifies barewords: pathlike
  (`/`, `./`, `../`, `~/`, `~`) → path; otherwise config group name
  (must exist). No preset-bareword branch — those are options now.
- `ManagementParser` reads `-p/-m/--yolo` for `add`, storing them as
  per-entry preset tokens in `groups.conf` (legacy bareword form,
  preserved for backwards compatibility with existing config files).
- `Resolver` expands named groups, dedupes by derived `cc-<name>`,
  layers per-entry config presets over merged CLI/dotfile defaults.
- `ensure_sources` creates missing sources with a single shared RC
  timestamp. `build_dashboard` creates the grouping session, sets
  `renumber-windows on`, `link-window`s each source, renames each
  linked window to the bare project name, and kills the stub shell.

### `Options` class (`lib/claude_tmux/options.rb`)

TOML cascade loader. Key behaviors:

- **Cascade** — walks `$PWD` upward; stops after `$HOME` (inclusive)
  or at `/` if `$PWD` is not under `$HOME`. Files are merged
  shallowest-first so deeper directories override shallower.
- **User-wide baseline** — `~/.config/cct/options.toml` applied first
  (lowest priority) under the walk-cascade.
- **Schema validation** — enum fields (`permission`, `model`) error
  on invalid values with the file path. Bools error on non-bool.
  Unknown top-level keys warn to stderr and continue (forward-compat).
- **Output shape** — plain hash keyed by `:permission`, `:model`,
  `:yolo`, `:rc`, `:project => { :name }`, `:group => { :label }`.

### `SessionName` module (`lib/claude_tmux/session_name.rb`)

Pure utility. `.compute(dir:, name:)` returns `cc-<basename>` with
name-argument priority over derivation. No `.cct-name` reading
(removed in v0.3 — replaced by `[project] name` in the TOML cascade).

### `Config` (`lib/claude_tmux/config.rb`)

INI-style parser/writer for `~/.config/cct/groups.conf`. Unchanged
structurally from v0.2; the per-entry preset tokens (bareword form)
are preserved for backwards compat with existing config files.

- Paths must start with `/` or `~/` (or bare `~`); relative paths
  rejected at parse and write time. `ccg add` special-cases `.` for
  `$PWD`.
- Same-category preset mutex still enforced at validation time
  (`plan yolo` → error). Permission category here includes `yolo`
  because historically that's how it behaved.
- `#save` is a full rewrite — comments and ordering are not preserved
  across `add`/`rm`. Use `ccg edit` for anything round-trippy.

### `Tmux` wrapper (`lib/claude_tmux/tmux.rb`)

Injectable dependency — `Project`, `Group`, and `Picker` all accept
`tmux:` so specs can pass `FakeTmux` (in `spec/spec_helper.rb`). All
argv is passed as discrete tokens (no shell). Methods that replace
the current process (`attach`, `new_session`, `switch_client`) call
`Kernel.send :exec, ...` — multi-arg form performs a direct
`execve(2)` with no shell. Dispatching via `send` sidesteps pattern-
based security-warning hooks that treat the bare built-in as shell.

### `Picker` class (`lib/claude_tmux/picker.rb`)

Wraps `sesh list | fzf | sesh connect`. Glyphs derive from substring
matches against `tmux capture-pane` output — pattern-matching Claude
Code's UI strings (`"esc to interrupt"`, `"Do you want"`, `"❯ 1."`),
brittle by nature. Matched strings live in the constant dict at the
top of the file; when Claude rewords a prompt and a glyph stops
updating, that's the first place to look.

## Release workflow

- Semver in `lib/claude_tmux/version.rb`; changelog in `CHANGELOG.md`.
- `bundle exec rake build` → `pkg/claude-tmux-<version>.gem`.
- `bundle exec rake release` tags, pushes, publishes (requires
  rubygems auth).
- The gemspec declares `{claude-tmux, cct, ccg, ccs}` as executables;
  `gem install` installs all four under `$GEM_HOME/bin/`.
- Runtime deps: `toml-rb ~> 2.2`. Dev deps: `rake`, `rspec`, `rubocop`.

## Migration notes (v0.2 → v0.3)

- Positional preset barewords removed. `cct plan sonnet` → `cct -p plan -m sonnet`.
- `.cct-name` removed. Convert to `.claude-tmux.toml` with
  `[project]\nname = "..."`.
- `sesh-pick` binary renamed to `ccs`. `install.sh` auto-cleans the
  old symlink. Users with tmux bindings referencing `sesh-pick` must
  update them.
- `cct group …` invocation form removed. Use `ccg …` or
  `claude-tmux group …` directly.
