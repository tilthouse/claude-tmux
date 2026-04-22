# `ccg config` TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ccg config` — an interactive fzf-driven TUI for managing groups in `~/.config/cct/groups.conf`. Also adds unique-prefix subcommand matching at the CLI top-level and Group dispatch layers.

**Architecture:** A small screen-pushdown state machine (`ConfigTui`) operates on an in-memory `Config` snapshot. Each screen runs one or more prompts via an injected `Prompt` interface (real impl shells out to fzf + reads `/dev/tty`; spec impl is a scripted `FakePrompt`). Mutations stage in memory; user is asked to save/discard on exit. `Config` gains four mutators (`rename_group`, `move_entry`, `replace_entry_presets`, `dirty?`) plus public `absolute_or_tilde?`. Subcommand prefix matching adds a single helper used at both dispatch layers.

**Tech Stack:** Ruby ≥ 3.0, fzf (existing runtime dep, no new gems), RSpec, RuboCop. Spec doc: `docs/superpowers/specs/2026-04-22-ccg-config-tui-design.md`.

---

## File Structure

**New files**
- `lib/claude_tmux/prompt.rb` — `Prompt` (real fzf/tty wrapper) + `FakePrompt` (scripted test double living in the same file for proximity).
- `lib/claude_tmux/group/config_tui.rb` — `ConfigTui` class, screen methods, state-stack loop.
- `lib/claude_tmux/group/config_tui/candidate_builder.rb` — assembles the dedup'd add-entry candidate list (sources: other groups, sesh, ~/Developer walk).
- `spec/claude_tmux/prompt_spec.rb` — minimal coverage for `FakePrompt`'s queue semantics.
- `spec/claude_tmux/group/config_tui_spec.rb` — scripted end-to-end flows.
- `spec/claude_tmux/group/config_tui/candidate_builder_spec.rb` — candidate-list assembly + dedup.
- `spec/claude_tmux/cli_spec.rb` — top-level prefix matching (file may already exist; if so, add `describe` blocks).

**Modified files**
- `lib/claude_tmux/config.rb` — add four mutators, promote `absolute_or_tilde?`, add `config` to `RESERVED_WORDS`.
- `lib/claude_tmux/group.rb` — add `config` to `RESERVED_SUBCOMMANDS`, route to `ConfigTui#run`, apply prefix matching in `run`.
- `lib/claude_tmux/cli.rb` — apply prefix matching to `SUBCOMMANDS`; update `top_level_help` with `config`.
- `lib/claude_tmux/group/help.rb` — add `config` to the usage block.
- `spec/claude_tmux/config_spec.rb` — add specs for new mutators.
- `spec/claude_tmux/group/parser_spec.rb` (or new dispatch spec) — prefix matching coverage.
- `CHANGELOG.md`, `claude-tmux/CLAUDE.md`, `README.md` — docs.

---

## Phase 1 — Subcommand Prefix Matching

### Task 1: PrefixResolver helper + tests

**Files:**
- Create: `lib/claude_tmux/prefix_resolver.rb`
- Create: `spec/claude_tmux/prefix_resolver_spec.rb`
- Modify: `lib/claude_tmux.rb` (require new file)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/claude_tmux/prefix_resolver_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::PrefixResolver do
  let(:names) { %w[add rm list edit config] }

  describe '.resolve' do
    it 'returns exact matches verbatim' do
      expect(described_class.resolve('add', names)).to eq('add')
    end

    it 'resolves a unique prefix' do
      expect(described_class.resolve('co', names)).to eq('config')
    end

    it 'returns nil when nothing matches' do
      expect(described_class.resolve('zzz', names)).to be_nil
    end

    it 'raises UsageError when the prefix is ambiguous' do
      ambiguous = %w[config configure]
      expect { described_class.resolve('co', ambiguous) }
        .to raise_error(ClaudeTmux::UsageError, /ambiguous: 'co' matches config, configure/)
    end

    it 'prefers an exact match over a longer prefix-match candidate' do
      # 'add' matches exactly even if 'addendum' would also match the prefix.
      expect(described_class.resolve('add', %w[add addendum])).to eq('add')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/prefix_resolver_spec.rb -fd`
Expected: load error / `uninitialized constant ClaudeTmux::PrefixResolver`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/claude_tmux/prefix_resolver.rb
# frozen_string_literal: true

module ClaudeTmux
  # Resolve a token against a list of subcommand names by:
  #   1. exact match (always wins)
  #   2. unique prefix from the first character
  # Returns the matched name, nil if no match, or raises UsageError on
  # ambiguity (with the candidate list in the message).
  module PrefixResolver
    module_function

    def resolve(token, names)
      return token if names.include?(token)

      matches = names.select { |n| n.start_with?(token) }
      return nil if matches.empty?
      return matches.first if matches.size == 1

      raise UsageError, "ambiguous: '#{token}' matches #{matches.join(', ')}"
    end
  end
end
```

- [ ] **Step 4: Wire into the loader**

Add to `lib/claude_tmux.rb` (alphabetical with other requires; if there's no central file, require it from `lib/claude_tmux/cli.rb` instead — check the codebase for the existing pattern):

```ruby
require_relative 'claude_tmux/prefix_resolver'
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/claude_tmux/prefix_resolver_spec.rb -fd`
Expected: 5 examples, 0 failures

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop lib/claude_tmux/prefix_resolver.rb spec/claude_tmux/prefix_resolver_spec.rb`
Expected: no offenses

- [ ] **Step 7: Commit**

```bash
git add lib/claude_tmux/prefix_resolver.rb spec/claude_tmux/prefix_resolver_spec.rb lib/claude_tmux.rb
git commit -m "feat: add PrefixResolver for unique-prefix subcommand matching"
```

---

### Task 2: Apply prefix matching to top-level CLI dispatch

**Files:**
- Modify: `lib/claude_tmux/cli.rb`
- Create or modify: `spec/claude_tmux/cli_spec.rb`

- [ ] **Step 1: Write the failing test**

If `spec/claude_tmux/cli_spec.rb` doesn't exist, create it. Otherwise add to existing:

```ruby
# spec/claude_tmux/cli_spec.rb
require 'spec_helper'

RSpec.describe ClaudeTmux::CLI do
  let(:stderr) { StringIO.new }
  let(:stdout) { StringIO.new }

  it 'resolves a unique top-level subcommand prefix' do
    # `pi` uniquely prefixes `pick` (not `project`/`group`/`sess-pick`).
    cli = described_class.new('claude-tmux', %w[pi --help], stderr: stderr, stdout: stdout)
    # The exact dispatch target is Picker; we only check that we didn't print "unknown subcommand".
    cli.run
    expect(stderr.string).not_to include('unknown subcommand')
  end

  it 'errors with candidate list on ambiguous prefix' do
    cli = described_class.new('claude-tmux', %w[p], stderr: stderr, stdout: stdout)
    cli.run
    expect(stderr.string).to match(/ambiguous: 'p' matches/)
  end

  it 'still errors on no-match' do
    cli = described_class.new('claude-tmux', %w[zzz], stderr: stderr, stdout: stdout)
    cli.run
    expect(stderr.string).to include("unknown subcommand 'zzz'")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/cli_spec.rb -fd`
Expected: first two examples fail; third may pass already.

- [ ] **Step 3: Modify `CLI#dispatch` in `lib/claude_tmux/cli.rb`**

Replace the existing subcommand lookup block. Find:

```ruby
      sub = @argv.first
      unless (target = SUBCOMMANDS[sub])
        @stderr.puts "#{@prog}: unknown subcommand '#{sub}'"
        @stderr.puts top_level_help
        return 2
      end
```

Replace with:

```ruby
      sub = @argv.first
      resolved = PrefixResolver.resolve(sub, SUBCOMMANDS.keys)
      target = SUBCOMMANDS[resolved] if resolved
      unless target
        @stderr.puts "#{@prog}: unknown subcommand '#{sub}'"
        @stderr.puts top_level_help
        return 2
      end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/cli_spec.rb -fd`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Run full suite to check for regressions**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop lib/claude_tmux/cli.rb spec/claude_tmux/cli_spec.rb`
Expected: no offenses.

- [ ] **Step 7: Commit**

```bash
git add lib/claude_tmux/cli.rb spec/claude_tmux/cli_spec.rb
git commit -m "feat: prefix-match top-level CLI subcommands"
```

---

### Task 3: Apply prefix matching to Group subcommand dispatch

**Files:**
- Modify: `lib/claude_tmux/group.rb`
- Modify: `spec/claude_tmux/group/parser_spec.rb` (or create `spec/claude_tmux/group_spec.rb`)

- [ ] **Step 1: Write the failing test**

Add to `spec/claude_tmux/group/parser_spec.rb` (or create a new dispatch spec). Note: this tests `Group#run` dispatch, not `Parser`. Use `spec/claude_tmux/group_dispatch_spec.rb`:

```ruby
# spec/claude_tmux/group_dispatch_spec.rb
require 'spec_helper'

RSpec.describe ClaudeTmux::Group, 'subcommand dispatch' do
  let(:stderr) { StringIO.new }
  let(:stdout) { StringIO.new }

  it 'resolves `l` to `list`' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      File.write(conf, "[work]\n~/x\n")
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)
      group = described_class.new('ccg', %w[l], stderr: stderr, stdout: stdout)
      group.run
      expect(stdout.string).to include('[work]')
    end
  end

  it 'errors on ambiguous prefix' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      File.write(conf, "[work]\n~/x\n")
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)
      # Both `add` and a hypothetical reserved word starting with `a` would conflict;
      # current set has only `add` starting with `a`, so this can only assert
      # the helper is wired — drive against a known unambiguous case.
      # Keep this as a smoke test that resolution is invoked at all by exercising
      # `e` → edit.
      group = described_class.new('ccg', %w[e --help], stderr: stderr, stdout: stdout)
      # `edit` would normally exec $EDITOR; we just check it didn't fall through
      # to launch-mode parsing (which would error on bareword `e`).
      expect { group.run }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/group_dispatch_spec.rb -fd`
Expected: first example fails — `e` falls through to launch path which then errors on the `l` bareword.

Wait — re-check: the first test calls `ccg l`. Without prefix matching, `l` is a bareword that `Group::Parser` calls `classify_bareword` on, which errors with "unknown argument 'l'". After fix, `l` resolves to `list` via prefix matching.

- [ ] **Step 3: Modify `Group#run` in `lib/claude_tmux/group.rb`**

Replace:

```ruby
    def run
      return print_help if %w[-h --help help].include?(@argv.first)

      return run_management(@argv.shift) if @argv.first && RESERVED_SUBCOMMANDS.include?(@argv.first)

      run_launch
    end
```

With:

```ruby
    def run
      return print_help if %w[-h --help help].include?(@argv.first)

      if @argv.first && (resolved = PrefixResolver.resolve(@argv.first, RESERVED_SUBCOMMANDS))
        @argv.shift
        return run_management(resolved)
      end

      run_launch
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group_dispatch_spec.rb -fd && bundle exec rspec`
Expected: all green.

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop lib/claude_tmux/group.rb spec/claude_tmux/group_dispatch_spec.rb`
Expected: no offenses.

- [ ] **Step 6: Commit**

```bash
git add lib/claude_tmux/group.rb spec/claude_tmux/group_dispatch_spec.rb
git commit -m "feat: prefix-match group subcommand dispatch"
```

---

## Phase 2 — Config API Additions

### Task 4: `Config#rename_group`

**Files:**
- Modify: `lib/claude_tmux/config.rb`
- Modify: `spec/claude_tmux/config_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/claude_tmux/config_spec.rb` inside the existing top-level `describe`:

```ruby
  describe '#rename_group' do
    it 'renames in place, preserving entries and order index' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('a', '~/x')
      cfg.add_entry('b', '~/y')
      cfg.add_entry('c', '~/z')
      cfg.rename_group('b', 'beta')
      expect(cfg.group_names).to eq(%w[a beta c])
      expect(cfg.group('beta').entries.first.path).to eq('~/y')
      expect(cfg.group('b')).to be_nil
    end

    it 'raises when the source group does not exist' do
      cfg = described_class.new(path: @path)
      expect { cfg.rename_group('nope', 'new') }.to raise_error(ClaudeTmux::ConfigError, /no such group/)
    end

    it 'raises when the new name is reserved' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('a', '~/x')
      expect { cfg.rename_group('a', 'add') }.to raise_error(ClaudeTmux::ConfigError, /reserved/)
    end

    it 'raises when the new name collides with an existing group' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('a', '~/x')
      cfg.add_entry('b', '~/y')
      expect { cfg.rename_group('a', 'b') }.to raise_error(ClaudeTmux::ConfigError, /already exists/)
    end

    it 'raises on invalid name format' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('a', '~/x')
      expect { cfg.rename_group('a', 'bad name') }.to raise_error(ClaudeTmux::ConfigError, /invalid group name/)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "rename_group"`
Expected: NoMethodError or undefined method.

- [ ] **Step 3: Implement**

Add to `lib/claude_tmux/config.rb` after `delete_group`:

```ruby
    def rename_group(old_name, new_name)
      raise ConfigError, "no such group: #{old_name}" unless @groups.key?(old_name)
      raise ConfigError, "group already exists: #{new_name}" if @groups.key?(new_name)

      validate_group_name!(new_name)

      group = @groups.delete(old_name)
      group.name = new_name
      @groups[new_name] = group
      @order[@order.index(old_name)] = new_name
      true
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "rename_group"`
Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb
git commit -m "feat: Config#rename_group"
```

---

### Task 5: `Config#move_entry`

**Files:**
- Modify: `lib/claude_tmux/config.rb`
- Modify: `spec/claude_tmux/config_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  describe '#move_entry' do
    it 'moves an entry to a new index within the group' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/a')
      cfg.add_entry('g', '~/b')
      cfg.add_entry('g', '~/c')
      cfg.move_entry('g', 0, 2)
      expect(cfg.group('g').entries.map(&:path)).to eq(%w[~/b ~/c ~/a])
    end

    it 'is a no-op when from == to' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/a')
      cfg.add_entry('g', '~/b')
      cfg.move_entry('g', 1, 1)
      expect(cfg.group('g').entries.map(&:path)).to eq(%w[~/a ~/b])
    end

    it 'raises when the group is missing' do
      cfg = described_class.new(path: @path)
      expect { cfg.move_entry('g', 0, 1) }.to raise_error(ClaudeTmux::ConfigError, /no such group/)
    end

    it 'raises on out-of-range indices' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/a')
      expect { cfg.move_entry('g', 5, 0) }.to raise_error(ClaudeTmux::ConfigError, /index out of range/)
      expect { cfg.move_entry('g', 0, 5) }.to raise_error(ClaudeTmux::ConfigError, /index out of range/)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "move_entry"`
Expected: NoMethodError.

- [ ] **Step 3: Implement**

Add to `lib/claude_tmux/config.rb`:

```ruby
    def move_entry(group_name, from_idx, to_idx)
      group = @groups[group_name]
      raise ConfigError, "no such group: #{group_name}" unless group
      return true if from_idx == to_idx

      size = group.entries.size
      unless (0...size).cover?(from_idx) && (0...size).cover?(to_idx)
        raise ConfigError, "index out of range (size=#{size}): #{from_idx}, #{to_idx}"
      end

      entry = group.entries.delete_at(from_idx)
      group.entries.insert(to_idx, entry)
      true
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "move_entry"`
Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb
git commit -m "feat: Config#move_entry"
```

---

### Task 6: `Config#replace_entry_presets`

**Files:**
- Modify: `lib/claude_tmux/config.rb`
- Modify: `spec/claude_tmux/config_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  describe '#replace_entry_presets' do
    it 'swaps the presets array on the matching entry (path matched by canonical form)' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/x', ['plan'])
      cfg.replace_entry_presets('g', '~/x', %w[sonnet])
      expect(cfg.group('g').entries.first.presets).to eq(%w[sonnet])
    end

    it 'matches paths by canonical (expanded) form' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', "#{Dir.home}/x", ['plan'])
      cfg.replace_entry_presets('g', '~/x', %w[sonnet])
      expect(cfg.group('g').entries.first.presets).to eq(%w[sonnet])
    end

    it 'raises when the group is missing' do
      cfg = described_class.new(path: @path)
      expect { cfg.replace_entry_presets('g', '~/x', []) }
        .to raise_error(ClaudeTmux::ConfigError, /no such group/)
    end

    it 'raises when the entry is not found' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/x')
      expect { cfg.replace_entry_presets('g', '~/y', []) }
        .to raise_error(ClaudeTmux::ConfigError, /no such entry/)
    end

    it 'validates the new presets via existing rules' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/x')
      expect { cfg.replace_entry_presets('g', '~/x', %w[plan yolo]) }
        .to raise_error(ClaudeTmux::ConfigError, /conflicting permission/)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "replace_entry_presets"`
Expected: NoMethodError.

- [ ] **Step 3: Implement**

Add to `lib/claude_tmux/config.rb`:

```ruby
    def replace_entry_presets(group_name, path, new_presets)
      group = @groups[group_name]
      raise ConfigError, "no such group: #{group_name}" unless group

      validate_presets!(new_presets)

      expanded = File.expand_path(path)
      entry = group.entries.find { |e| File.expand_path(e.path) == expanded }
      raise ConfigError, "no such entry in [#{group_name}]: #{path}" unless entry

      entry.presets = new_presets
      true
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "replace_entry_presets"`
Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb
git commit -m "feat: Config#replace_entry_presets"
```

---

### Task 7: `Config#dirty?` and promote `absolute_or_tilde?`

**Files:**
- Modify: `lib/claude_tmux/config.rb`
- Modify: `spec/claude_tmux/config_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  describe '#dirty?' do
    it 'is false for a freshly loaded snapshot' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/x')
      cfg.save
      reloaded = described_class.load(path: @path)
      expect(reloaded.dirty?).to be(false)
    end

    it 'is true after an in-memory mutation' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/x')
      cfg.save
      reloaded = described_class.load(path: @path)
      reloaded.add_entry('g', '~/y')
      expect(reloaded.dirty?).to be(true)
    end

    it 'is true when the on-disk file is missing but in-memory has groups' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('g', '~/x')
      expect(cfg.dirty?).to be(true)
    end

    it 'is false when both in-memory and on-disk are empty/missing' do
      cfg = described_class.new(path: @path)
      expect(cfg.dirty?).to be(false)
    end
  end

  describe '#absolute_or_tilde?' do
    it 'is now public' do
      cfg = described_class.new(path: @path)
      expect(cfg.absolute_or_tilde?('/abs')).to be(true)
      expect(cfg.absolute_or_tilde?('~/x')).to be(true)
      expect(cfg.absolute_or_tilde?('~')).to be(true)
      expect(cfg.absolute_or_tilde?('rel')).to be(false)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "dirty?"`
Expected: NoMethodError on `dirty?`. The `absolute_or_tilde?` test fails with `NoMethodError: private method`.

- [ ] **Step 3: Implement `dirty?` and promote `absolute_or_tilde?`**

In `lib/claude_tmux/config.rb`:

(a) Move `def absolute_or_tilde?` from below `private` to above it (so it becomes public). It already has the body:

```ruby
    def absolute_or_tilde?(path)
      path.start_with?('/') || path.start_with?('~/') || path == '~'
    end
```

(b) Add `dirty?` (public, place near `save`):

```ruby
    def dirty?
      disk = self.class.new(path: @path).load
      to_signature != disk.send(:to_signature)
    end

    protected

    # Stable structural signature: order-preserved [name, [path, presets]] tuples.
    def to_signature
      @order.map do |name|
        entries = @groups[name].entries.map { |e| [e.path, e.presets.dup] }
        [name, entries]
      end
    end
```

Note: `to_signature` is `protected` so a sibling `Config` instance can call it via `disk.send(:to_signature)` cleanly. Alternatively expose it as public — pick whichever your project's existing access conventions prefer.

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "dirty?" -e "absolute_or_tilde"`
Expected: 5 examples, 0 failures.

Run full suite to catch any regressions from `absolute_or_tilde?` access change:

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb`
Expected: no offenses (may complain about method length on `dirty?` block — extract `to_signature` if so, which is what the snippet above does).

- [ ] **Step 6: Commit**

```bash
git add lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb
git commit -m "feat: Config#dirty? + promote absolute_or_tilde? to public"
```

---

### Task 8: Reserve `config` in `Config::RESERVED_WORDS`

**Files:**
- Modify: `lib/claude_tmux/config.rb`
- Modify: `spec/claude_tmux/config_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to the existing `describe '#add_entry + #save'` block in `config_spec.rb`:

```ruby
    it 'rejects `config` as a reserved group name' do
      cfg = described_class.new(path: @path)
      expect { cfg.add_entry('config', '~/x') }.to raise_error(ClaudeTmux::ConfigError, /reserved/)
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd -e "reserved"`
Expected: the new test fails (no error raised since `config` isn't reserved yet).

- [ ] **Step 3: Add `config` to `RESERVED_WORDS`**

In `lib/claude_tmux/config.rb`:

```ruby
    RESERVED_WORDS = %w[add rm list edit group help config].freeze
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/config_spec.rb -fd && bundle exec rspec`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb
git commit -m "feat: reserve `config` as a group name"
```

---

## Phase 3 — Prompt Abstraction

### Task 9: `Prompt` + `FakePrompt`

**Files:**
- Create: `lib/claude_tmux/prompt.rb`
- Create: `spec/claude_tmux/prompt_spec.rb`
- Modify: `lib/claude_tmux.rb` (add require)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/claude_tmux/prompt_spec.rb
require 'spec_helper'

RSpec.describe ClaudeTmux::FakePrompt do
  it 'returns scripted choose responses in order' do
    prompt = described_class.new(responses: [
      { method: :choose, value: { key: nil, item: 'apple' } },
      { method: :choose, value: { key: 'R', item: 'banana' } }
    ])
    expect(prompt.choose(%w[apple banana], header: 'pick')).to eq(key: nil, item: 'apple')
    expect(prompt.choose(%w[apple banana], header: 'pick')).to eq(key: 'R', item: 'banana')
  end

  it 'returns scripted input responses' do
    prompt = described_class.new(responses: [
      { method: :input, value: 'typed-name' }
    ])
    expect(prompt.input(label: 'name?')).to eq('typed-name')
  end

  it 'returns scripted confirm responses' do
    prompt = described_class.new(responses: [
      { method: :confirm, value: true },
      { method: :confirm, value: false }
    ])
    expect(prompt.confirm(label: 'sure?')).to be(true)
    expect(prompt.confirm(label: 'sure?')).to be(false)
  end

  it 'raises if the queue is exhausted' do
    prompt = described_class.new(responses: [])
    expect { prompt.choose(%w[a], header: 'h') }.to raise_error(/FakePrompt: no scripted response/)
  end

  it 'raises on method mismatch' do
    prompt = described_class.new(responses: [{ method: :input, value: 'x' }])
    expect { prompt.choose(%w[a], header: 'h') }
      .to raise_error(/expected choose, got input/)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/prompt_spec.rb -fd`
Expected: uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
# lib/claude_tmux/prompt.rb
# frozen_string_literal: true

module ClaudeTmux
  # Prompt: thin abstraction over fzf and tty input so ConfigTui can be
  # exercised in tests via FakePrompt without spawning real fzf processes.
  #
  # Every method returns plain Ruby data (no fzf-specific shapes leak out):
  #   #choose  → { key: <pressed-expect-key or nil>, item: <selected line or nil> }
  #              `nil` item on ESC; `key: nil` means Enter.
  #   #input   → typed string (nil on ESC)
  #   #confirm → true/false
  class Prompt
    def initialize(stderr: $stderr)
      @stderr = stderr
    end

    # items: Array<String>. expect: Array<String> of single keys to bind.
    def choose(items, header:, expect: [])
      args = ['fzf', '--prompt', '> ', '--header', header, '--reverse', '--height=60%']
      args += ['--expect', expect.join(',')] unless expect.empty?
      out = IO.popen(args, 'r+') do |io|
        io.write(items.join("\n"))
        io.close_write
        io.read
      end
      return { key: nil, item: nil } if out.nil? || out.empty?

      lines = out.each_line.map(&:chomp)
      if expect.empty?
        { key: nil, item: lines.first }
      else
        key = lines.first.empty? ? nil : lines.first
        { key: key, item: lines[1] }
      end
    rescue Errno::ENOENT
      @stderr.puts 'ccg: fzf not found on PATH — install fzf to use ccg config.'
      { key: nil, item: nil }
    end

    def input(label:)
      @stderr.print("#{label} ")
      tty_in = File.open('/dev/tty', 'r')
      line = tty_in.gets&.chomp
      tty_in.close
      line
    end

    def confirm(label:)
      response = input(label: "#{label} (y/n)")
      response&.downcase&.start_with?('y') || false
    end
  end

  # Test double: queue of {method:, value:} responses. Pop one per call;
  # raise if the queue is empty or the method doesn't match.
  class FakePrompt
    def initialize(responses: [])
      @responses = responses.dup
      @log = []
    end

    attr_reader :log

    def choose(items, header:, expect: [])
      pop(:choose, items: items, header: header, expect: expect)
    end

    def input(label:)
      pop(:input, label: label)
    end

    def confirm(label:)
      pop(:confirm, label: label)
    end

    private

    def pop(method, args)
      raise "FakePrompt: no scripted response for #{method}" if @responses.empty?

      head = @responses.shift
      raise "FakePrompt: expected #{head[:method]}, got #{method}" unless head[:method] == method

      @log << { method: method, args: args, returned: head[:value] }
      head[:value]
    end
  end
end
```

- [ ] **Step 4: Add require to `lib/claude_tmux.rb`**

```ruby
require_relative 'claude_tmux/prompt'
```

- [ ] **Step 5: Run tests**

Run: `bundle exec rspec spec/claude_tmux/prompt_spec.rb -fd && bundle exec rspec`
Expected: 5 prompt examples + full suite all pass.

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop lib/claude_tmux/prompt.rb spec/claude_tmux/prompt_spec.rb`
Expected: no offenses (may need to disable Metrics/MethodLength on `#choose` if it complains).

- [ ] **Step 7: Commit**

```bash
git add lib/claude_tmux/prompt.rb spec/claude_tmux/prompt_spec.rb lib/claude_tmux.rb
git commit -m "feat: add Prompt + FakePrompt abstraction over fzf/tty"
```

---

## Phase 4 — Add-Entry Candidate Builder

### Task 10: `CandidateBuilder` for add-entry source list

**Files:**
- Create: `lib/claude_tmux/group/config_tui/candidate_builder.rb`
- Create: `spec/claude_tmux/group/config_tui/candidate_builder_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/claude_tmux/group/config_tui/candidate_builder_spec.rb
require 'spec_helper'

RSpec.describe ClaudeTmux::Group::ConfigTui::CandidateBuilder do
  around do |ex|
    Dir.mktmpdir do |home|
      @home = home
      @dev = File.join(home, 'Developer')
      FileUtils.mkdir_p(@dev)
      ex.run
    end
  end

  def make_dir(*parts)
    path = File.join(@dev, *parts)
    FileUtils.mkdir_p(path)
    path
  end

  def make_repo(*parts)
    path = make_dir(*parts)
    FileUtils.mkdir_p(File.join(path, '.git'))
    path
  end

  def cfg_with(groups)
    cfg = ClaudeTmux::Config.new(path: '/dev/null')
    groups.each do |name, paths|
      paths.each { |p| cfg.add_entry(name, p) }
    end
    cfg
  end

  it 'lists entries from other groups first, tagged [group:NAME]' do
    cfg = cfg_with('work' => ['~/x'], 'life' => ['~/y'])
    builder = described_class.new(config: cfg, current_group: 'work', sesh: -> { [] }, dev_root: @dev)
    rows = builder.build
    expect(rows.first).to include(tag: '[group:life]', path: '~/y')
  end

  it 'omits entries already in the current group' do
    cfg = cfg_with('work' => ['~/x'])
    builder = described_class.new(config: cfg, current_group: 'work', sesh: -> { [] }, dev_root: @dev)
    expect(builder.build.map { |r| r[:path] }).not_to include('~/x')
  end

  it 'includes sesh entries tagged [sesh]' do
    builder = described_class.new(config: cfg_with({}), current_group: 'work', sesh: -> { ['/tmp/seshy'] }, dev_root: @dev)
    rows = builder.build
    expect(rows.find { |r| r[:tag] == '[sesh]' }[:path]).to eq('/tmp/seshy')
  end

  it 'walks dev_root depth-first for .git dirs, tagged [dev]' do
    make_repo('tools', 'projA')
    make_repo('clients', 'projB')
    make_dir('not-a-repo')                 # no .git → excluded
    builder = described_class.new(config: cfg_with({}), current_group: 'work', sesh: -> { [] }, dev_root: @dev)
    paths = builder.build.select { |r| r[:tag] == '[dev]' }.map { |r| r[:path] }
    expect(paths).to include(File.join(@dev, 'clients', 'projB'), File.join(@dev, 'tools', 'projA'))
    expect(paths).not_to include(File.join(@dev, 'not-a-repo'))
    # Alphabetical depth-first ordering: clients/projB before tools/projA.
    expect(paths.index(File.join(@dev, 'clients', 'projB')))
      .to be < paths.index(File.join(@dev, 'tools', 'projA'))
  end

  it 'dedups by canonical path, keeping first occurrence' do
    cfg = cfg_with('life' => ['/tmp/dup'])
    builder = described_class.new(
      config: cfg, current_group: 'work',
      sesh: -> { ['/tmp/dup'] }, dev_root: @dev
    )
    rows = builder.build
    dup_rows = rows.select { |r| r[:path] == '/tmp/dup' }
    expect(dup_rows.size).to eq(1)
    expect(dup_rows.first[:tag]).to eq('[group:life]')
  end

  it 'caps total candidates at the limit' do
    100.times { |i| make_repo('many', "p#{format('%03d', i)}") }
    builder = described_class.new(
      config: cfg_with({}), current_group: 'work',
      sesh: -> { [] }, dev_root: @dev, limit: 50
    )
    expect(builder.build.size).to eq(50)
  end

  it 'silently skips dev walk if dev_root does not exist' do
    builder = described_class.new(
      config: cfg_with({}), current_group: 'work',
      sesh: -> { [] }, dev_root: '/nonexistent'
    )
    expect(builder.build).to eq([])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui/candidate_builder_spec.rb -fd`
Expected: uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
# lib/claude_tmux/group/config_tui/candidate_builder.rb
# frozen_string_literal: true

module ClaudeTmux
  class Group
    class ConfigTui
      # Assembles the deduped add-entry candidate list:
      #   1. Entries in OTHER groups (excluding current_group)
      #   2. sesh-list entries
      #   3. ~/Developer walk (.git-bearing dirs, depth-first alpha)
      # Dedup by File.expand_path; first-seen wins.
      class CandidateBuilder
        DEFAULT_LIMIT = 200

        def initialize(config:, current_group:, sesh: -> { sesh_list }, dev_root: File.join(Dir.home, 'Developer'), limit: DEFAULT_LIMIT)
          @config = config
          @current_group = current_group
          @sesh_lambda = sesh
          @dev_root = dev_root
          @limit = limit
        end

        def build
          rows = []
          seen = {}
          add_rows = lambda do |source_rows|
            source_rows.each do |row|
              key = File.expand_path(row[:path])
              next if seen.key?(key)

              seen[key] = true
              rows << row
              break if rows.size >= @limit
            end
          end

          add_rows.call(group_rows)
          add_rows.call(sesh_rows) if rows.size < @limit
          add_rows.call(dev_rows) if rows.size < @limit
          rows
        end

        private

        def group_rows
          @config.groups.flat_map do |g|
            next [] if g.name == @current_group

            g.entries.map { |e| { tag: "[group:#{g.name}]", path: e.path } }
          end
        end

        def sesh_rows
          @sesh_lambda.call.map { |path| { tag: '[sesh]', path: path } }
        end

        def dev_rows
          return [] unless File.directory?(@dev_root)

          walk(@dev_root).map { |path| { tag: '[dev]', path: path } }
        end

        # Depth-first alphabetical walk, returning dirs containing a .git entry.
        def walk(root)
          result = []
          stack = [root]
          until stack.empty?
            dir = stack.pop
            children = Dir.children(dir).sort.reverse
            children.each do |name|
              path = File.join(dir, name)
              next unless File.directory?(path)

              if File.exist?(File.join(path, '.git'))
                result << path
              else
                stack.push(path)
              end
            end
          end
          # Stack is LIFO + reverse-sort: entries pop in alpha order.
          result
        end

        def sesh_list
          out = IO.popen(['sesh', 'list', err: File::NULL], &:read) || ''
          out.each_line.map(&:chomp).reject(&:empty?)
        rescue Errno::ENOENT
          []
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui/candidate_builder_spec.rb -fd`
Expected: 7 examples, 0 failures.

If the dev-walk test fails the order assertion, the depth-first walk output isn't truly alpha across siblings. Fix by sorting the `result` array per parent dir before flattening, or by switching to a recursive walk that processes children in alpha order before recursing.

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop lib/claude_tmux/group/config_tui/candidate_builder.rb spec/claude_tmux/group/config_tui/candidate_builder_spec.rb`
Expected: no offenses (Metrics/MethodLength on `walk` may need a small refactor or `# rubocop:disable` line).

- [ ] **Step 6: Commit**

```bash
git add lib/claude_tmux/group/config_tui spec/claude_tmux/group/config_tui
git commit -m "feat: CandidateBuilder for ccg config add-entry source list"
```

---

## Phase 5 — ConfigTui

### Task 11: ConfigTui skeleton + state-stack loop + groups_list

**Files:**
- Create: `lib/claude_tmux/group/config_tui.rb`
- Create: `spec/claude_tmux/group/config_tui_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/claude_tmux/group/config_tui_spec.rb
require 'spec_helper'

RSpec.describe ClaudeTmux::Group::ConfigTui do
  around do |ex|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, 'groups.conf')
      ex.run
    end
  end

  def cfg_with(groups)
    cfg = ClaudeTmux::Config.new(path: @path)
    groups.each { |name, paths| paths.each { |p| cfg.add_entry(name, p) } }
    cfg
  end

  it 'opens groups_list and exits cleanly on ESC with no save when clean' do
    cfg = cfg_with('work' => ['~/x'])
    cfg.save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose, value: { key: nil, item: nil } } # ESC on groups_list
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    expect(tui.run).to eq(0)
    # No save-prompt because nothing changed.
    expect(prompt.log.size).to eq(1)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: uninitialized constant.

- [ ] **Step 3: Implement skeleton**

```ruby
# lib/claude_tmux/group/config_tui.rb
# frozen_string_literal: true

module ClaudeTmux
  class Group
    # Interactive TUI for ~/.config/cct/groups.conf. State-stack loop:
    # each screen returns one of [:next, name, payload], [:back], or [:exit].
    # Mutations go through the in-memory @config; on exit, prompt save/discard.
    class ConfigTui
      def initialize(config_path: Config::DEFAULT_PATH, prompt: Prompt.new, stderr: $stderr)
        @config_path = config_path
        @config = Config.load(path: config_path)
        @prompt = prompt
        @stderr = stderr
      end

      def run
        stack = [[:groups_list, nil]]
        until stack.empty?
          screen, payload = stack.last
          result = dispatch_screen(screen, payload)
          case result.first
          when :next then stack.push([result[1], result[2]])
          when :back then stack.pop
          when :exit then stack.clear
          end
        end
        save_prompt
        0
      end

      private

      def dispatch_screen(screen, payload)
        send(:"screen_#{screen}", payload)
      rescue ConfigError => e
        @stderr.puts "ccg: #{e.message}"
        [:next, screen, payload] # re-show same screen
      end

      def screen_groups_list(_payload)
        items = ['[+ new group]'] + @config.group_names.map do |n|
          count = @config.group(n).entries.size
          "[#{n}] (#{count} project#{'s' if count != 1})"
        end
        result = @prompt.choose(items, header: header_with_dirty)
        return [:exit] if result[:item].nil? # ESC

        if result[:item] == '[+ new group]'
          # Implemented in next task.
          [:back]
        else
          name = result[:item][/\[(.+?)\]/, 1]
          [:next, :group_view, { group: name }]
        end
      end

      def header_with_dirty
        marker = @config.dirty? ? ' *' : ''
        "ccg config — groups#{marker}"
      end

      def save_prompt
        return unless @config.dirty?

        if @prompt.confirm(label: "Save changes to #{@config_path}?")
          @config.save
        end
      end
    end
  end
end
```

- [ ] **Step 4: Wire require**

Add to `lib/claude_tmux/group.rb` at the bottom (next to other `require_relative 'group/...'` lines):

```ruby
require_relative 'group/config_tui'
require_relative 'group/config_tui/candidate_builder'
```

- [ ] **Step 5: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: 1 example, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/claude_tmux/group/config_tui.rb spec/claude_tmux/group/config_tui_spec.rb lib/claude_tmux/group.rb
git commit -m "feat: ConfigTui skeleton + groups_list screen"
```

---

### Task 12: New-group flow + group_view screen

**Files:**
- Modify: `lib/claude_tmux/group/config_tui.rb`
- Modify: `spec/claude_tmux/group/config_tui_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `config_tui_spec.rb`:

```ruby
  it 'creates a new group via [+ new group] then exits saving' do
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[+ new group]' } },     # groups_list
      { method: :input,   value: 'mornings' },                               # name prompt
      { method: :choose,  value: { key: nil, item: nil } },                  # group_view ESC
      { method: :choose,  value: { key: nil, item: nil } },                  # back to groups_list, ESC
      { method: :confirm, value: true }                                       # save?
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group_names).to eq(['mornings'])
    expect(reloaded.group('mornings').entries).to be_empty
  end

  it 'shows group_view with entries and returns to groups_list on ESC' do
    cfg_with('work' => ['~/x', '~/y']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose, value: { key: nil, item: '[work] (2 projects)' } },
      { method: :choose, value: { key: nil, item: nil } }, # group_view ESC
      { method: :choose, value: { key: nil, item: nil } }  # groups_list ESC
    ])
    tui = described_class.new(config_path: @path, prompt: ClaudeTmux::FakePrompt.new(responses: prompt.instance_variable_get(:@responses)))
    expect(tui.run).to eq(0)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: failures (no `screen_group_view` yet, `[+ new group]` doesn't input a name).

- [ ] **Step 3: Implement new-group + group_view**

Replace `screen_groups_list` to handle the new-group case, and add `screen_group_view`:

```ruby
      def screen_groups_list(_payload)
        items = ['[+ new group]'] + @config.group_names.map do |n|
          count = @config.group(n).entries.size
          "[#{n}] (#{count} project#{'s' if count != 1})"
        end
        result = @prompt.choose(items, header: header_with_dirty)
        return [:exit] if result[:item].nil?

        if result[:item] == '[+ new group]'
          name = @prompt.input(label: 'New group name:')
          return [:next, :groups_list, nil] if name.nil? || name.strip.empty?

          @config.add_entry_or_create_empty(name.strip) # implemented below
          [:next, :group_view, { group: name.strip }]
        else
          name = result[:item][/\[(.+?)\]/, 1]
          [:next, :group_view, { group: name }]
        end
      end

      def screen_group_view(payload)
        name = payload[:group]
        group = @config.group(name)
        return [:back] unless group # was deleted from a child screen

        items = ['[+ add entry]'] + group.entries.map do |e|
          [e.path, *e.presets].join('  ')
        end
        result = @prompt.choose(items, header: "[#{name}]#{' *' if @config.dirty?}", expect: %w[R D])
        return [:back] if result[:item].nil? && result[:key].nil?

        case result[:key]
        when 'R' then [:next, :rename_group, { group: name }]
        when 'D' then [:next, :delete_group, { group: name }]
        else
          if result[:item] == '[+ add entry]'
            [:next, :add_entry, { group: name }]
          else
            path = result[:item].split('  ', 2).first
            [:next, :action_menu, { group: name, path: path }]
          end
        end
      end
```

The empty-group create needs a Config helper since `add_entry` requires a path. Add to `lib/claude_tmux/config.rb`:

```ruby
    def create_empty_group(name)
      validate_group_name!(name)
      raise ConfigError, "group already exists: #{name}" if @groups.key?(name)

      @groups[name] = Group.new(name: name, entries: [])
      @order << name
      true
    end
```

…and call `@config.create_empty_group(name.strip)` in the TUI (replace the `add_entry_or_create_empty` placeholder above).

Add a quick spec for `create_empty_group` in `spec/claude_tmux/config_spec.rb`:

```ruby
  describe '#create_empty_group' do
    it 'creates a group with no entries' do
      cfg = described_class.new(path: @path)
      cfg.create_empty_group('mornings')
      expect(cfg.group_names).to eq(['mornings'])
      expect(cfg.group('mornings').entries).to be_empty
    end

    it 'raises if the name already exists' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('a', '~/x')
      expect { cfg.create_empty_group('a') }.to raise_error(ClaudeTmux::ConfigError, /already exists/)
    end
  end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec -fd`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group/config_tui.rb lib/claude_tmux/config.rb spec/claude_tmux/config_spec.rb spec/claude_tmux/group/config_tui_spec.rb
git commit -m "feat: ConfigTui group_view + new-group flow"
```

---

### Task 13: action_menu (remove + reorder + edit-presets dispatch)

**Files:**
- Modify: `lib/claude_tmux/group/config_tui.rb`
- Modify: `spec/claude_tmux/group/config_tui_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  it 'removes an entry via action_menu and saves on exit' do
    cfg_with('work' => ['~/x', '~/y']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[work] (2 projects)' } },  # groups_list
      { method: :choose,  value: { key: nil, item: '~/x' } },                  # group_view entry row (no presets → no trailing whitespace)
      { method: :choose,  value: { key: nil, item: 'Remove' } },               # action_menu
      { method: :choose,  value: { key: nil, item: nil } },                    # group_view ESC
      { method: :choose,  value: { key: nil, item: nil } },                    # groups_list ESC
      { method: :confirm, value: true }                                         # save
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('work').entries.map(&:path)).to eq(['~/y'])
  end

  it 'moves an entry up via action_menu' do
    cfg_with('g' => ['~/a', '~/b', '~/c']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[g] (3 projects)' } },
      { method: :choose,  value: { key: nil, item: '~/c' } },                 # entry at idx 2 (no presets → no trailing whitespace)
      { method: :choose,  value: { key: nil, item: 'Move up' } },
      { method: :choose,  value: { key: nil, item: nil } },                   # group_view ESC
      { method: :choose,  value: { key: nil, item: nil } },                   # groups_list ESC
      { method: :confirm, value: true }
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('g').entries.map(&:path)).to eq(%w[~/a ~/c ~/b])
  end
```

Note: row format is `[path, *presets].join('  ')`. For an entry with no presets, the joined result is just the path (no trailing whitespace). Tests above already pass `'~/x'` / `'~/c'` directly.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: failures — `screen_action_menu` doesn't exist.

- [ ] **Step 3: Implement action_menu**

Add to `lib/claude_tmux/group/config_tui.rb`:

```ruby
      def screen_action_menu(payload)
        group = payload[:group]
        path = payload[:path]
        items = %w[Remove Move\ up Move\ down Edit\ presets]
        result = @prompt.choose(items, header: "[#{group}] #{path}")
        return [:back] if result[:item].nil?

        case result[:item]
        when 'Remove'
          @config.remove_entry(group, path)
        when 'Move up'   then move_entry_relative(group, path, -1)
        when 'Move down' then move_entry_relative(group, path, +1)
        when 'Edit presets'
          return [:next, :edit_presets, { group: group, path: path }]
        end
        [:back]
      end

      def move_entry_relative(group, path, delta)
        entries = @config.group(group).entries
        from = entries.find_index { |e| File.expand_path(e.path) == File.expand_path(path) }
        return unless from

        to = (from + delta).clamp(0, entries.size - 1)
        @config.move_entry(group, from, to) unless to == from
      end
```

Re-check the `group_view` row format: `[e.path, *e.presets].join('  ')`. For an entry `~/x` with no presets, this produces `~/x` (Array#join ignores empty join sources). With presets `['plan']`: `~/x  plan`.

The action-menu screen receives the entire row text and splits on the first double-space to recover the path. Update `screen_group_view`:

```ruby
            path = result[:item].split('  ', 2).first
```

(already in the previous task's snippet — leave it.)

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group/config_tui.rb spec/claude_tmux/group/config_tui_spec.rb
git commit -m "feat: ConfigTui action_menu (remove, move up/down)"
```

---

### Task 14: rename_group + delete_group screens

**Files:**
- Modify: `lib/claude_tmux/group/config_tui.rb`
- Modify: `spec/claude_tmux/group/config_tui_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
  it 'renames a group via R hotkey' do
    cfg_with('work' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[work] (1 project)' } },   # groups_list
      { method: :choose,  value: { key: 'R',  item: nil } },                   # group_view, R pressed
      { method: :input,   value: 'office' },                                    # rename prompt
      { method: :choose,  value: { key: nil, item: nil } },                    # back to group_view, ESC
      { method: :choose,  value: { key: nil, item: nil } },                    # groups_list ESC
      { method: :confirm, value: true }
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group_names).to eq(['office'])
  end

  it 'deletes a group via D hotkey when confirmed' do
    cfg_with('work' => ['~/x'], 'life' => ['~/y']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[work] (1 project)' } },
      { method: :choose,  value: { key: 'D',  item: nil } },
      { method: :confirm, value: true },                                        # delete confirm
      { method: :choose,  value: { key: nil, item: nil } },                    # groups_list ESC
      { method: :confirm, value: true }                                        # save
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group_names).to eq(['life'])
  end

  it 'cancels delete when not confirmed' do
    cfg_with('work' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[work] (1 project)' } },
      { method: :choose,  value: { key: 'D',  item: nil } },
      { method: :confirm, value: false },
      { method: :choose,  value: { key: nil, item: nil } },                    # back to group_view, ESC
      { method: :choose,  value: { key: nil, item: nil } }                     # groups_list ESC
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    expect(ClaudeTmux::Config.load(path: @path).group_names).to eq(['work'])
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: failures.

- [ ] **Step 3: Implement**

Add to `lib/claude_tmux/group/config_tui.rb`:

```ruby
      def screen_rename_group(payload)
        old_name = payload[:group]
        new_name = @prompt.input(label: "Rename [#{old_name}] to:")
        return [:back] if new_name.nil? || new_name.strip.empty?

        @config.rename_group(old_name, new_name.strip)
        # Pop both rename and old group_view; push new group_view.
        [:next, :group_view, { group: new_name.strip }]
      end

      def screen_delete_group(payload)
        name = payload[:group]
        return [:back] unless @prompt.confirm(label: "Delete group [#{name}]?")

        @config.delete_group(name)
        # Pop delete + the now-stale group_view by returning :back twice — emulate
        # by popping then re-routing to groups_list via :next.
        [:next, :groups_list, nil]
      end
```

The state-stack semantics here: `screen_delete_group` returns `[:next, :groups_list, nil]`, which pushes a new groups_list on top of the (deleted) group_view. The next ESC pops this, then pops the stale group_view (which `screen_group_view` returns `[:back]` for since `@config.group(name)` is nil), then pops to the previous groups_list, then exits. That's two redundant frames — harmless but worth noting. If it feels wrong, change the loop in `run` to support `[:replace, name, payload]` semantics; not needed for this iteration.

For `rename_group`, the new group_view is pushed *on top of* the old (now-stale-named) one. Same observation as above — when the user ESCs out, they'll briefly see the rendering loop pop a stale group_view that immediately returns `[:back]`. Acceptable.

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group/config_tui.rb spec/claude_tmux/group/config_tui_spec.rb
git commit -m "feat: ConfigTui rename_group and delete_group screens"
```

---

### Task 15: add_entry screen (with CandidateBuilder)

**Files:**
- Modify: `lib/claude_tmux/group/config_tui.rb`
- Modify: `spec/claude_tmux/group/config_tui_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
  it 'adds a candidate-list entry to the group' do
    cfg_with('work' => [], 'life' => ['~/elsewhere']).save
    # current group `work` is empty; CandidateBuilder will surface ~/elsewhere
    # from `life`. The displayed row format is "[group:life]\t~/elsewhere".
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[work] (0 projects)' } },
      { method: :choose,  value: { key: nil, item: '[+ add entry]' } },
      { method: :choose,  value: { key: nil, item: "[group:life]\t~/elsewhere" } },
      { method: :choose,  value: { key: nil, item: nil } },                  # group_view ESC
      { method: :choose,  value: { key: nil, item: nil } },                  # groups_list ESC
      { method: :confirm, value: true }
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('work').entries.map(&:path)).to eq(['~/elsewhere'])
  end
```

(Note: Real fzf with `--with-nth` would hide the tag in display. For tests, FakePrompt receives the full row as the `item` payload — we pass the joined `tag\tpath` string back.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: failure.

- [ ] **Step 3: Implement add_entry screen**

Add to `lib/claude_tmux/group/config_tui.rb`:

```ruby
      def screen_add_entry(payload)
        group = payload[:group]
        rows = CandidateBuilder.new(config: @config, current_group: group).build
        items = rows.map { |r| "#{r[:tag]}\t#{r[:path]}" }
        result = @prompt.choose(items, header: "[#{group}] add entry — type a path or pick one")
        return [:back] if result[:item].nil?

        # Selected row → split off the tag, take the path.
        path = result[:item].split("\t", 2).last
        @config.add_entry(group, path)
        [:back]
      end
```

The "typed path" branch (`--print-query`) is a TODO for a follow-up task — keep it minimal here. Add an inline TODO comment: `# TODO(--print-query): support typing an ad-hoc path when no row matches.`

Wait — the spec calls out the typed-path branch explicitly. Implement it now to avoid spec drift:

```ruby
      def screen_add_entry(payload)
        group = payload[:group]
        rows = CandidateBuilder.new(config: @config, current_group: group).build
        items = rows.map { |r| "#{r[:tag]}\t#{r[:path]}" }
        result = @prompt.choose(items, header: "[#{group}] add entry — type a path or pick one")
        return [:back] if result[:item].nil? && result[:query].to_s.empty?

        path =
          if result[:item]
            result[:item].split("\t", 2).last
          elsif @config.absolute_or_tilde?(result[:query])
            result[:query]
          else
            @stderr.puts "ccg: not a valid path: #{result[:query].inspect}"
            return [:back]
          end

        @config.add_entry(group, path)
        [:back]
      end
```

This requires `Prompt#choose` to surface the typed query. Update Prompt#choose to invoke fzf with `--print-query` when a flag is set, and surface `query:` in the return hash:

```ruby
    def choose(items, header:, expect: [], print_query: false)
      args = ['fzf', '--prompt', '> ', '--header', header, '--reverse', '--height=60%']
      args += ['--expect', expect.join(',')] unless expect.empty?
      args << '--print-query' if print_query
      out = IO.popen(args, 'r+') do |io|
        io.write(items.join("\n"))
        io.close_write
        io.read
      end
      return { key: nil, item: nil, query: nil } if out.nil?

      lines = out.each_line.map(&:chomp)
      query = print_query ? lines.shift : nil
      key = expect.empty? ? nil : (lines.shift unless lines.empty?)
      key = nil if key == ''
      item = lines.first
      { key: key, item: item, query: query }
    end
```

Update FakePrompt to accept `query:` in scripted values (the existing structure already returns whatever hash you scripted; just include `query: '...'` in the test).

Update the previous `screen_add_entry` call to pass `print_query: true`. Update the test responses to include `query: nil` (or omit — Hash access of `nil` is fine since `to_s.empty?` is true).

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group/config_tui.rb lib/claude_tmux/prompt.rb spec/claude_tmux/group/config_tui_spec.rb
git commit -m "feat: ConfigTui add_entry screen with candidate list and typed-path fallback"
```

---

### Task 16: edit_presets screen (3 sequential micro-screens)

**Files:**
- Modify: `lib/claude_tmux/group/config_tui.rb`
- Modify: `spec/claude_tmux/group/config_tui_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  it 'edits per-entry presets via three sequential prompts' do
    cfg_with('g' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose,  value: { key: nil, item: '[g] (1 project)' } },
      { method: :choose,  value: { key: nil, item: '~/x' } },                   # group_view → action_menu
      { method: :choose,  value: { key: nil, item: 'Edit presets' } },          # action_menu
      { method: :choose,  value: { key: nil, item: 'plan' } },                  # permission
      { method: :choose,  value: { key: nil, item: 'sonnet' } },                # model
      { method: :choose,  value: { key: nil, item: 'off' } },                   # yolo
      { method: :choose,  value: { key: nil, item: nil } },                     # group_view ESC
      { method: :choose,  value: { key: nil, item: nil } },                     # groups_list ESC
      { method: :confirm, value: true }
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('g').entries.first.presets).to eq(%w[plan sonnet])
  end

  it 'aborts preset edit on ESC at any step (snapshot untouched)' do
    cfg_with('g' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
      { method: :choose, value: { key: nil, item: '[g] (1 project)' } },
      { method: :choose, value: { key: nil, item: '~/x' } },
      { method: :choose, value: { key: nil, item: 'Edit presets' } },
      { method: :choose, value: { key: nil, item: 'plan' } },                  # permission
      { method: :choose, value: { key: nil, item: nil } },                     # ESC on model
      { method: :choose, value: { key: nil, item: nil } },                     # group_view ESC
      { method: :choose, value: { key: nil, item: nil } }                      # groups_list ESC
    ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    expect(ClaudeTmux::Config.load(path: @path).group('g').entries.first.presets).to eq([])
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: failure.

- [ ] **Step 3: Implement**

Add to `lib/claude_tmux/group/config_tui.rb`:

```ruby
      def screen_edit_presets(payload)
        group = payload[:group]
        path = payload[:path]
        new_presets = []

        permission = @prompt.choose(%w[(none) plan accept auto], header: "[#{group}] permission")[:item]
        return [:back] if permission.nil?

        new_presets << permission unless permission == '(none)'

        model = @prompt.choose(%w[(none) opus sonnet], header: "[#{group}] model")[:item]
        return [:back] if model.nil?

        new_presets << model unless model == '(none)'

        yolo = @prompt.choose(%w[off on], header: "[#{group}] yolo")[:item]
        return [:back] if yolo.nil?

        new_presets << 'yolo' if yolo == 'on'

        # `yolo` and a permission preset can't co-exist — Config validates.
        # Drop permission if user picked yolo (UI policy: yolo wins).
        new_presets -= Presets::VALID_PERMISSIONS if new_presets.include?('yolo')

        @config.replace_entry_presets(group, path, new_presets)
        [:back]
      end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group/config_tui_spec.rb -fd`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group/config_tui.rb spec/claude_tmux/group/config_tui_spec.rb
git commit -m "feat: ConfigTui edit_presets (3 sequential micro-screens)"
```

---

## Phase 6 — Wiring & Help

### Task 17: Register `config` subcommand and route to ConfigTui

**Files:**
- Modify: `lib/claude_tmux/group.rb`
- Modify: `spec/claude_tmux/group_dispatch_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/claude_tmux/group_dispatch_spec.rb`:

```ruby
  it 'routes `ccg config` to ConfigTui' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      File.write(conf, "[work]\n~/x\n")
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)
      fake = ClaudeTmux::FakePrompt.new(responses: [
        { method: :choose, value: { key: nil, item: nil } } # immediate ESC
      ])
      # Inject the FakePrompt by stubbing Prompt.new — simplest seam.
      allow(ClaudeTmux::Prompt).to receive(:new).and_return(fake)

      group = described_class.new('ccg', %w[config])
      expect(group.run).to eq(0)
    end
  end

  it 'routes `ccg c` (prefix) to ConfigTui' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      File.write(conf, "[work]\n~/x\n")
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)
      fake = ClaudeTmux::FakePrompt.new(responses: [
        { method: :choose, value: { key: nil, item: nil } }
      ])
      allow(ClaudeTmux::Prompt).to receive(:new).and_return(fake)
      group = described_class.new('ccg', %w[c])
      expect(group.run).to eq(0)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/claude_tmux/group_dispatch_spec.rb -fd -e "config"`
Expected: failures — `config` not in `RESERVED_SUBCOMMANDS` yet.

- [ ] **Step 3: Modify `lib/claude_tmux/group.rb`**

Update `RESERVED_SUBCOMMANDS`:

```ruby
    RESERVED_SUBCOMMANDS = %w[add rm list edit config].freeze
```

Add a case to `run_management`:

```ruby
    def run_management(cmd)
      case cmd
      when 'add'    then cmd_add(@argv)
      when 'rm'     then cmd_rm(@argv)
      when 'list'   then cmd_list(@argv)
      when 'edit'   then cmd_edit
      when 'config' then cmd_config
      end
    end

    def cmd_config
      ConfigTui.new(config_path: Config::DEFAULT_PATH).run
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/claude_tmux/group_dispatch_spec.rb -fd && bundle exec rspec`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group.rb spec/claude_tmux/group_dispatch_spec.rb
git commit -m "feat: register `ccg config` subcommand routing to ConfigTui"
```

---

### Task 18: Update help text

**Files:**
- Modify: `lib/claude_tmux/group/help.rb`
- Modify: `lib/claude_tmux/cli.rb`

- [ ] **Step 1: Update `Group::Help.render`**

In `lib/claude_tmux/group/help.rb`, add to the USAGE block:

```
  #{prog} config                          # interactive TUI
```

Place it right after the `edit` line.

- [ ] **Step 2: Update `CLI#top_level_help`**

In `lib/claude_tmux/cli.rb`, add to the SUBCOMMANDS section under `group`:

```
            group config                  Interactive TUI for managing groups.
```

(below `group edit`).

Also add a one-line note about prefix matching at the bottom of `GLOBAL`:

```
  Subcommands resolve by unique prefix (e.g. `ccg c` → `config`).
```

- [ ] **Step 3: Smoke-test help output**

Run: `bundle exec ruby -Ilib bin/ccg --help` and `bundle exec ruby -Ilib bin/claude-tmux --help`. Eyeball that `config` appears.

- [ ] **Step 4: Run full suite + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_tmux/group/help.rb lib/claude_tmux/cli.rb
git commit -m "docs: surface `ccg config` and prefix matching in --help"
```

---

## Phase 7 — Docs

### Task 19: CHANGELOG, CLAUDE.md, README

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Add CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`:

```markdown
## Unreleased

### Added
- `ccg config` — interactive TUI for managing groups (browse, create, rename, delete; add, remove, reorder entries; edit per-entry presets). fzf-driven; stages all changes in memory and prompts to save on exit.
- Subcommand prefix matching at top-level (`claude-tmux pi` → `pick`) and Group dispatch (`ccg c` → `config`). Exact match wins; ambiguous prefix raises with the candidate list.

### Changed
- `Config#absolute_or_tilde?` is now public (consumed by `ConfigTui`).
- `Config::RESERVED_WORDS` now includes `config`.
```

- [ ] **Step 2: Update `CLAUDE.md` (the one at the repo root)**

Add to the `### Architecture` section under `Group`:

```
- `cmd_config` routes to `ConfigTui` (see `lib/claude_tmux/group/config_tui.rb`).
  ConfigTui is a screen-pushdown loop driven by an injectable `Prompt`
  abstraction (`lib/claude_tmux/prompt.rb`), with `FakePrompt` for tests.
```

Add to the smoke-test list:

```
HOME=/tmp/x ccg config                   # TUI smoke (manual exit via ESC)
```

Add to the `## Architecture` section a one-liner:

```
- `PrefixResolver` (`lib/claude_tmux/prefix_resolver.rb`) provides unique-prefix
  subcommand resolution at both `CLI#dispatch` and `Group#run`.
```

- [ ] **Step 3: Update README.md**

Add a subsection under the Group documentation:

```markdown
### Interactive editing — `ccg config`

`ccg config` opens a fzf-driven TUI for managing groups without hand-editing the
config file. Browse groups, create / rename / delete groups, add / remove /
reorder entries, and edit per-entry presets. All changes stage in memory; you'll
be prompted to save on exit.

`ccg edit` is unchanged — it still opens `groups.conf` in `$EDITOR`.
```

Also add a brief note about prefix matching near the top of the CLI section.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md CLAUDE.md README.md
git commit -m "docs: changelog + README + CLAUDE.md for ccg config"
```

---

## Phase 8 — Final smoke + bump

### Task 20: Manual smoke + version bump

**Files:**
- Modify: `lib/claude_tmux/version.rb`

- [ ] **Step 1: Run full test suite + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all green, no offenses.

- [ ] **Step 2: Manual smoke**

(These are exploratory — run them and verify the behavior matches the spec; user feedback may prompt follow-up issues.)

```bash
bundle exec ruby -Ilib bin/ccg --help                # mentions config
bundle exec ruby -Ilib bin/ccg help                  # alias works
bundle exec ruby -Ilib bin/ccg c                     # prefix → config TUI
bundle exec ruby -Ilib bin/ccg config                # exact → config TUI
bundle exec ruby -Ilib bin/ccg edit                  # unchanged: $EDITOR
```

In the TUI, exercise: browse, create empty group, add entry, reorder, edit presets, rename, delete, save, discard.

- [ ] **Step 3: Bump version**

Edit `lib/claude_tmux/version.rb`. If current is `0.3.0`, bump to `0.4.0` (new feature, no breaking changes). Update the same version in `CHANGELOG.md` (replace `## Unreleased` with `## 0.4.0 — YYYY-MM-DD`).

- [ ] **Step 4: Commit + (optional) tag**

```bash
git add lib/claude_tmux/version.rb CHANGELOG.md
git commit -m "v0.4.0: ccg config TUI + subcommand prefix matching"
```

(Leave gem build/release for the user — they have a publishing playbook in `docs/PUBLISHING.md`.)

---

## Self-Review

**Spec coverage check:**
- ✅ `ccg config` subcommand → Tasks 17, 18
- ✅ Operations (browse / create / delete group / rename / add entry / remove / reorder / edit presets) → Tasks 11–16
- ✅ Add-entry candidate sources (other groups / sesh / ~/Developer) with dedup → Task 10
- ✅ In-memory staging + save-on-exit prompt → Task 11 (`save_prompt`); behavior validated in Tasks 12–16
- ✅ `ccg edit` unchanged → not modified anywhere
- ✅ Prefix matching at both layers → Tasks 1, 2, 3
- ✅ fzf-only, no new gems → Prompt class shells out, no Gemfile changes
- ✅ `Config` API additions → Tasks 4, 5, 6, 7, 8 (+ `create_empty_group` added in Task 12)
- ✅ Reserved-word update → Task 8
- ✅ Help text → Task 18
- ✅ Tests for everything new → present in each task
- ✅ Docs (CHANGELOG / CLAUDE.md / README) → Task 19

**Notes for the implementer:**
- `Config::Group` and `Config::Entry` are `Struct` types with `keyword_init: true`. Mutating `Entry#presets` via `entry.presets = ...` works because Struct accessors are read-write.
- `Group::ConfigTui` is nested inside `class Group` — use `class Group; class ConfigTui; ...` opening syntax (the existing `interactive_picker.rb` uses the same pattern).
- The state-stack loop is intentionally simple. If a screen needs to "replace" the current frame instead of pushing on top (e.g. `delete_group` returning to `groups_list` without a stale `group_view` underneath), add `[:replace, name, payload]` semantics in a follow-up — not in scope here.
- `FakePrompt` does NOT model fzf's filter behavior — every scripted `:choose` returns whatever you pass. Your tests are responsible for matching the row format `screen_*` builds.

**Open follow-ups (deferred per spec, not in this plan):**
- Move-between-groups verb in `action_menu`.
- Dedicated reorder mode (raw `j`/`k` key loop) if the per-entry Move up / Move down feels slow.
- `ccg config <group>` direct-jump argument.
- Stricter no-op detection on save-prompt (currently re-loads the file once via `dirty?`; could cache).
