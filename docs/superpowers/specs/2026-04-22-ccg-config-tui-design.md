# `ccg config` — Interactive TUI for Editing Groups

## Context

`ccg` already has a launch-side picker (`ccg` bare) but no way to **edit** groups beyond `ccg add`/`ccg rm` (one operation per invocation) and `ccg edit` (opens `groups.conf` in `$EDITOR`, raw text). Common edit flows — rename a group, reorder entries, toggle a per-entry preset, see what's already in other groups before adding a new entry — are clunky against the file format and slow against one-shot subcommands.

A dedicated TUI obviates the file-edit path for routine work, while `ccg edit` stays as the escape hatch.

This spec also folds in **subcommand prefix matching** (`ccg c`, `ccg co`, `ccg con`, `ccg conf`, `ccg config` all resolve to `config` as long as the prefix is unique), because both the new subcommand and the prefix rule touch CLI dispatch and ship as one cohesive UX change.

## Goals

1. New subcommand `ccg config` enters an interactive TUI for managing groups.
2. Operations supported: browse groups, create empty group, delete group, rename group, add entry, remove entry, reorder entries within a group, edit per-entry presets.
3. Add-entry candidate list aggregates from existing entries in other groups, `sesh list`, and a `~/Developer` walk — deduped, in that priority order.
4. All edits stage in memory; user is prompted to save/discard on quit.
5. `ccg edit` retains its current behavior (opens `groups.conf` in `$EDITOR`).
6. Subcommand dispatch supports unique-prefix matching at every level.
7. fzf-based rendering — no new runtime gem dependencies.

## Non-goals

- Editing `~/.config/cct/options.toml` or `.claude-tmux.toml` files. Out of scope.
- Launching projects from the TUI. `ccg` bare already covers that.
- Preserving comments / blank lines / entry order across save (`Config#save` is already a full rewrite — this spec doesn't change that).
- Moving entries between groups. (Achievable today via remove-then-add; can be added later if desired.)
- Cross-platform consideration beyond what fzf already supports.

## Command surface

```
ccg config                  # enter TUI
ccg conf                    # prefix-resolves to config (also c, co, con)
ccg edit                    # unchanged: $EDITOR groups.conf
```

Prefix matching applies at:
- **Top-level**: against `CLI::SUBCOMMANDS.keys` (`project`, `group`, `pick`, `sess-pick`).
- **Group subcommands**: against `Group::RESERVED_SUBCOMMANDS` (`add`, `rm`, `list`, `edit`, `config`).

Resolution rule: exact match wins; otherwise unique prefix from the first character resolves; ambiguous prefix raises `UsageError` listing the candidates. No-match behavior depends on the layer:

- **Top-level (`CLI#dispatch`)** — no match falls through to today's behavior (`stderr.puts "unknown subcommand"`, print top-level help, exit 2).
- **Group subcommands (`Group#run`)** — no match falls through to the existing launch path so the token is classified by `Group::Parser` (path / named group / unknown-argument error).

## TUI architecture

### State machine

The TUI is a small screen-pushdown loop. Each screen is a method that runs one or more prompts and returns one of:

- `:next, payload` — push a new screen
- `:back` — pop to previous screen
- `:exit` — bubble out to save-prompt

```
groups_list ──► group_view ──► action_menu ──► remove
                            │              ├─► move_up
                            │              ├─► move_down
                            │              └─► edit_presets
                            ├─► add_entry
                            ├─► rename_group
                            └─► delete_group (confirm)
```

`groups_list` also offers `[+ new group]`, prompting for a name and pushing `group_view` against the new empty group.

### Screens

**`groups_list`** (entry)
- Items: `[+ new group]`, then one line per group (`[work] (3 projects)`).
- Enter on a group → `group_view`.
- Enter on `[+ new group]` → name prompt → push `group_view` for the new group.
- ESC → save-prompt → exit. (`q` is not bound here — fzf would treat it as a search character.)

**`group_view`** (one group)
- Header line shows group name and a `*` if the snapshot is dirty.
- Items: `[+ add entry]`, then one line per entry (`<path>  <presets...>`).
- Enter on an entry → `action_menu`.
- Enter on `[+ add entry]` → `add_entry`.
- fzf `--bind`: `R` rename group, `D` delete group (confirm).
- ESC → back to `groups_list`.

**`action_menu`** (per entry)
- Items: `Remove`, `Move up`, `Move down`, `Edit presets`. ESC = back.
- Each selection mutates the snapshot then returns to `group_view`.
- Reorder is bound here (rather than as a dedicated reorder mode) for fzf-native discoverability. May be revisited if usage proves clunky.

**`add_entry`** (see §"Add-entry candidate list")
- Single fzf invocation with `--print-query` against the deduped candidate list.
- On Enter:
  - Selected row → use that path.
  - No selection but typed query is path-shaped (starts with `/`, `~/`, or is `~` — same predicate as `Config#absolute_or_tilde?`, which is promoted from private to public for reuse) → use as ad-hoc path (`File.expand_path`).
  - Else → error message printed to stderr, screen re-launched.

**`rename_group`**
- Single-line input prompt; validates against `GROUP_NAME_RE` and `Config::RESERVED_WORDS`.
- Mutates snapshot; back to `group_view`.

**`delete_group`**
- Confirm prompt (`Delete group [foo]? (y/n)`); on `y`, deletes from snapshot and pops back to `groups_list`.

**`edit_presets`** (per entry)
- Three sequential micro-screens, each one fzf with current value pre-highlighted via `--query`:
  1. Permission: `(none) | plan | accept | auto`
  2. Model: `(none) | opus | sonnet`
  3. Yolo: `off | on`
- ESC at any step aborts the entire edit (snapshot untouched).
- Final selection set replaces the entry's `presets` array. `Config`'s same-category-mutex validation re-runs on save (defense in depth — UI only offers valid combinations).

**Save prompt**
- Skip entirely if snapshot equals on-disk file.
- Otherwise: `Save changes to ~/.config/cct/groups.conf? (y/n)`. `n` exits 0 with no write; `y` calls `Config#save`.

## Add-entry candidate list

Built once per `add_entry` invocation, in priority order, deduped by `File.expand_path`:

1. **Entries from other groups** — every `Entry.path` in the snapshot except those already in the current group. Tagged `[group:<name>]` for visual context.
2. **`sesh list`** output — same shell-out the launch picker uses. Tagged `[sesh]`.
3. **`~/Developer` walk** — depth-first, alphabetical, only directories that look like project roots (contain `.git` *or* are immediate children of a `~/Developer/<bucket>/` dir). Capped at 200 candidates to keep fzf snappy. Tagged `[dev]`.

First occurrence wins on dedup, so an existing-group entry beats a sesh entry beats a Developer-walk entry.

If `sesh` is not on PATH, source 2 is skipped silently. If `~/Developer` does not exist, source 3 is skipped silently. Source 1 always runs.

## Persistence model

The TUI operates on an in-memory `Config` snapshot loaded at start. Every mutator (add, remove, rename, reorder, preset-edit, delete-group) updates that snapshot only. On exit:

- If `snapshot == on-disk`, exit 0 silently.
- Else, prompt save/discard. `y` writes via `Config#save`; `n` discards.

Errors raised from `Config` mutators (reserved name, mutex violation, invalid path, etc.) are caught at the screen layer, printed to stderr as a single line (`ccg: <message>`), and the same screen is re-launched.

## Config API additions

`lib/claude_tmux/config.rb` gains:

- `rename_group(old_name, new_name)` — rename in place; preserves entries and order index; validates new name.
- `move_entry(group_name, from_idx, to_idx)` — reorder entries within a group.
- `replace_entry_presets(group_name, path, new_presets)` — swap one entry's presets array.
- `dirty?` — compare in-memory state to on-disk file (cheap re-load + structural diff). Used by save-prompt.
- `absolute_or_tilde?(path)` — promoted from `private` to public so `ConfigTui` can validate ad-hoc paths typed at the add-entry prompt.

All mutators raise `ConfigError` on validation failure. Existing mutators (`add_entry`, `remove_entry`, `delete_group`) are unchanged.

`Config::RESERVED_WORDS` gains `config`.

## CLI dispatch — prefix matching

A small helper applied at both dispatch layers:

```ruby
def resolve_subcommand(token, names)
  return token if names.include?(token)
  matches = names.select { |n| n.start_with?(token) }
  return matches.first if matches.size == 1
  raise UsageError, "ambiguous: '#{token}' matches #{matches.join(', ')}" if matches.size > 1
  nil
end
```

Applied in:
- `CLI#dispatch` against `SUBCOMMANDS.keys`.
- `Group#run` against `RESERVED_SUBCOMMANDS`.

Current set is collision-free at the first character: `a`/`r`/`l`/`e`/`c` resolve uniquely. Future additions that collide will require deeper prefixes (e.g. adding `clone` later would force `co`/`cl`).

## File layout

**New files**
- `lib/claude_tmux/group/config_tui.rb` — `ConfigTui` class with private `screen_*` methods.
- `lib/claude_tmux/group/config_tui/` — split screen helpers here when `config_tui.rb` grows past ~200 lines (`add_entry_picker.rb`, `preset_editor.rb`, `developer_walker.rb`). Start as one file.
- `lib/claude_tmux/prompt.rb` — `Prompt` class encapsulating fzf and `/dev/tty` interactions, with a `FakePrompt` test double.
- `spec/claude_tmux/group/config_tui_spec.rb` — scripted-flow specs.
- `spec/claude_tmux/prompt_spec.rb` — minimal coverage of the real Prompt's input parsing (no fzf in CI).

**Modified files**
- `lib/claude_tmux/group.rb` — register `config` in `RESERVED_SUBCOMMANDS`, route to `ConfigTui#run`, apply prefix matching in `run`.
- `lib/claude_tmux/group/help.rb` — add `config` to the usage block.
- `lib/claude_tmux/cli.rb` — apply prefix matching to `SUBCOMMANDS`; update `top_level_help`.
- `lib/claude_tmux/config.rb` — add four mutators above; add `config` to `RESERVED_WORDS`.

## Testing strategy

- Inject a `Prompt` interface into `ConfigTui`. Real impl shells out to fzf and reads from `/dev/tty`; spec impl is a scripted queue of canned responses (`FakePrompt`).
- `ConfigTui` specs drive scripted flows end-to-end: e.g. "open → pick group A → add entry from candidate list → reorder → quit → save", asserting the resulting `Config` state and whether `Config#save` was invoked.
- `Config` mutator specs are pure-data (no Prompt needed); cover happy paths plus each `ConfigError` case.
- Prefix-matching specs for both `CLI` and `Group` dispatch — exact match wins, unique prefix resolves, ambiguous prefix raises with candidate list.
- No integration tests against real fzf — that stays a manual smoke check (added to the `cct`/`ccg`/`ccs` smoke-test list in `claude-tmux/CLAUDE.md`).

## Migration / docs

- `CHANGELOG.md` — note `ccg config` and prefix matching as new in the next minor.
- `claude-tmux/CLAUDE.md` — add `ccg config` to the smoke-test shape list and a one-line architectural note for the `Prompt` injection pattern.
- `README.md` — short subsection on `ccg config`.
- No breaking changes; `ccg edit` behavior is preserved.

## Open questions / deferred

- Reorder UX. Starting with `Move up` / `Move down` in the per-entry action menu. If usage shows this is slow for groups with many entries, add a dedicated reorder mode (single screen, raw-key `j`/`k` to move highlighted item, Enter to commit).
- Move-between-groups. Not in scope; implementable later as an action-menu verb that calls `remove_entry` + `add_entry`.
- `ccg config` from inside an existing group context (e.g. `ccg config foo` to jump straight to group `foo`'s view). Not in initial scope — adds parsing complexity for a small UX win.
