# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Config do
  around do |ex|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, 'groups.conf')
      ex.run
    end
  end

  def write(contents)
    File.write(@path, contents)
  end

  describe '#load' do
    it 'parses sections, paths, and presets' do
      write(<<~CONF)
        [morning]
        ~/Developer/projA
        ~/Developer/projB plan
        ~/Developer/projC plan sonnet

        # another group
        [evening]
        /abs/path
      CONF

      cfg = described_class.load(path: @path)
      expect(cfg.group_names).to eq(%w[morning evening])
      expect(cfg.group('morning').entries.size).to eq(3)
      expect(cfg.group('morning').entries.last.presets).to eq(%w[plan sonnet])
      expect(cfg.group('evening').entries.first.path).to eq('/abs/path')
    end

    it 'rejects relative paths' do
      write("[g]\nrelative/path\n")
      expect { described_class.load(path: @path) }.to raise_error(ClaudeTmux::ConfigError, /relative paths/)
    end

    it 'rejects unknown presets in entries' do
      write("[g]\n~/x bogus\n")
      expect { described_class.load(path: @path) }.to raise_error(ClaudeTmux::ConfigError, /unknown preset/)
    end

    it 'rejects entries before any section' do
      write("~/stray\n[g]\n~/ok\n")
      expect { described_class.load(path: @path) }.to raise_error(ClaudeTmux::ConfigError, /outside of any/)
    end
  end

  describe '#add_entry + #save' do
    it 'persists a new group with tilde-canonicalized path' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('morning', "#{Dir.home}/Developer/projA", ['plan'])
      cfg.save

      reloaded = described_class.load(path: @path)
      entries = reloaded.group('morning').entries
      expect(entries.size).to eq(1)
      expect(entries.first.path).to eq('~/Developer/projA')
      expect(entries.first.presets).to eq(['plan'])
    end

    it 'updates an existing entry rather than duplicating' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('morning', '~/x', ['plan'])
      cfg.add_entry('morning', '~/x', ['sonnet'])
      expect(cfg.group('morning').entries.size).to eq(1)
      expect(cfg.group('morning').entries.first.presets).to eq(['sonnet'])
    end

    it 'rejects reserved group names' do
      cfg = described_class.new(path: @path)
      expect { cfg.add_entry('add', '~/x') }.to raise_error(ClaudeTmux::ConfigError, /reserved/)
    end

    it 'rejects `config` as a reserved group name' do
      cfg = described_class.new(path: @path)
      expect { cfg.add_entry('config', '~/x') }.to raise_error(ClaudeTmux::ConfigError, /reserved/)
    end
  end

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

  describe '#replace_entry_presets' do
    it 'swaps the presets array on the matching entry' do
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

  describe '#remove_entry / #delete_group' do
    it 'removes a single entry and leaves the group' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('morning', '~/a')
      cfg.add_entry('morning', '~/b')
      expect(cfg.remove_entry('morning', '~/a')).to be(true)
      expect(cfg.group('morning').entries.map(&:path)).to eq(['~/b'])
    end

    it 'deletes the whole group' do
      cfg = described_class.new(path: @path)
      cfg.add_entry('morning', '~/a')
      expect(cfg.delete_group('morning')).to be(true)
      expect(cfg.group_names).to be_empty
    end
  end
end
