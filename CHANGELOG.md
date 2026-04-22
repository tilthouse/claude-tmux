# Changelog

All notable changes to this project will be documented in this file. Format:
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), adherence to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-04-22

### Added

- `ccg config` — interactive TUI for managing groups (browse, create,
  rename, delete; add, remove, reorder entries; edit per-entry presets).
  fzf-driven; stages all changes in memory and prompts to save on exit.
- Subcommand prefix matching at top-level (`claude-tmux pi` → `pick`)
  and Group dispatch (`ccg c` → `config`). Exact match wins; ambiguous
  prefix raises with the candidate list.
- `ccg help` accepted as an alias for `ccg --help`.

### Fixed

- Bare `ccg` no longer crashes with `TypeError` when the interactive
  picker yields a selection — picker output now flows through the
  normal Resolver pipeline.

### Changed

- `Config#absolute_or_tilde?` is now public (consumed by `ConfigTui`).
- `Config::RESERVED_WORDS` now includes `config` and `help`.

## [0.3.0] - 2026-04-21

### Breaking

- Positional preset barewords are no longer accepted. Migrate:
  - `cct plan sonnet` → `cct -p plan -m sonnet`
  - `cct yolo opus` → `cct --yolo -m opus`
  - `ccg morning plan` → `ccg -p plan morning`
- `.cct-name` file support removed. Migrate each repo to a
  `.claude-tmux.toml` with `[project] name = "..."`.
- `sesh-pick` binary renamed to `ccs`. `install.sh` auto-removes the
  legacy symlink; tmux keybindings referencing `sesh-pick` must be
  updated to `ccs`.
- `cct group …` invocation form removed. Use `ccg …` or
  `claude-tmux group …` directly.

### Added

- Single canonical subcommand tree:
  `claude-tmux <project|group|sess-pick|pick> [options] [positional]`.
- Three symlink shortcuts: `cct` → `project`, `ccg` → `group`,
  `ccs` → `sess-pick`.
- Option flags replacing the old bareword presets:
  `-p/--permission {plan|accept|auto}`, `-m/--model {opus|sonnet}`,
  `--yolo`. Same across `project`, `group`, and `group add`.
- `project` accepts an optional positional `DIR`:
  `cct ~/Developer/foo` runs claude in that directory with name
  derived from its git root.
- Cascading TOML defaults:
  - Per-project `.claude-tmux.toml` (merged walking `$PWD` → `$HOME`
    inclusive, deeper dirs winning).
  - User-wide `~/.config/cct/options.toml` (lowest-priority baseline).
  - Keys: `permission`, `model`, `yolo`, `rc`, `[project] name`,
    `[group] label`. Unknown keys logged and ignored.
- `gemfile`/`bundler/setup` auto-load in bin scripts so local-symlink
  usage resolves `toml-rb` without a separate `gem install`.

### Changed

- `ClaudeTmux::Cct` class renamed to `ClaudeTmux::Project`.
- `ClaudeTmux::Project` module (session-name utility) renamed to
  `ClaudeTmux::SessionName` to make room for the class; API is now
  `SessionName.compute(dir:, name:)`.
- `Presets` module reduced to a value→flag mapping utility. Parser
  and validation logic lives in the subcommand parsers and `Config`.

### Removed

- Bareword preset classification in the parsers.
- `.cct-name` reading.
- `Presets.resolve`, `Presets.category`, `Presets.preset?`,
  `Presets::ALL` (replaced by direct enum membership checks).

### Dependencies

- Adds `toml-rb ~> 2.2` as a runtime dependency.

## [0.2.0] - 2026-04-20

Ruby rewrite of the entire tool. Added group mode (`ccg`), `-c`/`-r`
guards, RSpec test suite.

## [0.1.0] - 2026-04-19

Initial bash release: per-project `cct`, presets, `sesh-pick` decorator.
