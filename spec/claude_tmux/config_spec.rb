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
