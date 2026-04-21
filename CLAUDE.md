# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

Three bash scripts. No build, no tests, no lint. User-facing docs live in `README.md`; verbose flag/semantics reference lives in the `--help` heredoc inside `bin/claude-tmux` — keep both in sync when changing behavior.

## Commands

- `./install.sh` — idempotent installer that symlinks `bin/claude-tmux` and `bin/sesh-pick` into `~/.local/bin/`, plus `cct → claude-tmux`. Pre-existing regular files are preserved as `.bak`; existing symlinks are replaced. Safe to re-run after every change.
- `cct --help` / `claude-tmux --help` — verify flag parsing / help text still renders after edits.
- Manual smoke test: `cct`, `cct plan sonnet`, `cct --rc`, `cct -c`, `cct -n scratch` — the four shape categories (default, presets, modifier-with-timestamp, name override).

Because the installed paths under `~/.local/bin/` are symlinks into this repo, edits take effect on the next `cct` invocation. Don't edit the installed symlinks; edit the files under `bin/`.

## Architecture

### `bin/claude-tmux` (main entry point, aliased as `cct`)

Flow: parse args → compute session name → launch tmux.

**Invocation-name mirroring.** `prog=$(basename "$0")` is threaded through the entire `--help` heredoc as `$prog`. Examples in help render as `cct` or `claude-tmux` depending on how the user called it. Preserve this when editing help — don't hardcode either name.

**Argument parser (lines ~122–191).** Hand-rolled `while/case` loop, not `getopts`. Four shapes in one pass:
- Flag options: `-n/--name <arg>`, `--rc`, `-r/--resume [id]`, `-c/--continue`.
- Positional presets in two mutually-exclusive categories: permission (`plan|accept|auto|yolo`) and model (`opus|sonnet`). Presets from different categories compose; same category errors.
- `--` ends parsing; remainder goes verbatim to `claude` via `extra_args`.
- Unknown `-*` or bareword → hard error with suggestion to use `--`.

Two subtle spots:
- **`-r` optional id consumption** (lines ~142–149): after `-r`, the next token is consumed as an id *only* if it isn't another known flag, preset, or `--`. The exclusion list is hardcoded — **if you add a new preset keyword, add it here too**, or `-r` followed by that preset will swallow the preset as a resume id.
- **`yolo` maps to `--dangerously-skip-permissions`**, `accept` maps to `--permission-mode acceptEdits`; the other two permission presets pass through unchanged. Keep this mapping table in sync with Claude CLI's actual flag names.

**Session-name computation.** Precedence chain in `project_name()`: `-n` override → `<git-root>/.cct-name` (first line, whitespace stripped) → `basename $(git rev-parse --show-toplevel)` → `basename $PWD`. Every result is prefixed `cc-`. The `cc-*` prefix is what lets `sesh-pick`'s decorator identify Claude sessions.

**Timestamp rule.** The tmux session name is always `cc-<basename>` — no modifier or preset ever appends to it. The YY-MM-DD-HHMM timestamp is used in exactly one place: the `--remote-control-session-name-prefix` value passed to claude when `--rc` is set, so the mobile picker distinguishes invocations that share one tmux session. For a concurrent distinct session in the same project, users pass `-n <name>`. Attach-or-create semantics mean `-c`/`-r` silently no-op on an existing session (the flags only take effect on create); that's intentional and documented in `--help`.

**Launch branch.** Inside tmux (`$TMUX` set): create detached + `switch-client` (new-session won't nest). Outside tmux: plain attach-or-new. Attach preserves the *original* flags; presets/flags only apply on create — document any change to this behavior in `--help`.

### `bin/sesh-pick` (decorated picker)

Wraps `sesh list | fzf | sesh connect` and prepends a per-session glyph derived from `tmux capture-pane -S -30`. The glyph logic is **pattern-matching against Claude Code's UI strings** (`"esc to interrupt"`, `"Do you want"`, `"❯ 1."`) — these are brittle by nature. They live at the top of the file in a single `case` statement; when Claude rewords a prompt and a glyph stops updating, that's the first place to look. Tab is used as the fzf delimiter so session names with spaces survive.

### `install.sh`

Idempotent symlinker. The `cct` symlink points at the *installed* `claude-tmux` symlink (not directly at the repo file) — so updating one updates both. The `.bak` preservation only triggers for regular files; pre-existing symlinks are replaced without backup.
