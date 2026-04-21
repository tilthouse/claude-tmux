# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::SessionName do
  around do |ex|
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { ex.run }
    end
  end

  def init_git
    system('git', 'init', '-q', @dir)
    system('git', '-C', @dir, 'commit', '--allow-empty', '-q', '-m', 'init')
  end

  describe '.compute' do
    it 'prefixes the git-root basename with cc-' do
      init_git
      expect(described_class.compute(dir: @dir)).to eq("cc-#{File.basename(@dir)}")
    end

    it 'honors the name argument over derivation' do
      init_git
      expect(described_class.compute(dir: @dir, name: 'scratch')).to eq('cc-scratch')
    end

    it 'falls back to cwd basename when not in a git repo' do
      expect(described_class.compute(dir: @dir)).to eq("cc-#{File.basename(@dir)}")
    end

    it 'treats empty name as absent' do
      init_git
      expect(described_class.compute(dir: @dir, name: ''))
        .to eq("cc-#{File.basename(@dir)}")
    end

    it 'does not read .cct-name (removed in v0.3)' do
      init_git
      File.write(File.join(@dir, '.cct-name'), "should-be-ignored\n")
      expect(described_class.compute(dir: @dir)).to eq("cc-#{File.basename(@dir)}")
    end
  end
end
