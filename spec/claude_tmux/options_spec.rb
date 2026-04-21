# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Options do
  let(:logger) { StringIO.new }

  around do |ex|
    Dir.mktmpdir do |home|
      Dir.mktmpdir(nil, home) do |dev|
        Dir.mktmpdir(nil, dev) do |proj|
          @home = home
          @dev = dev
          @proj = proj
          @user_config = File.join(home, '.config', 'cct', 'options.toml')
          ex.run
        end
      end
    end
  end

  def write(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def load_at(dir)
    described_class.load(dir: dir, home: @home, user_config: @user_config, logger: logger)
  end

  describe '.load' do
    it 'returns blank defaults when no files exist' do
      result = load_at(@proj)
      expect(result[:permission]).to be_nil
      expect(result[:model]).to be_nil
      expect(result[:yolo]).to be(false)
      expect(result[:rc]).to be(false)
      expect(result[:project][:name]).to be_nil
      expect(result[:group][:label]).to be_nil
    end

    it 'reads a single project dotfile' do
      write(File.join(@proj, '.claude-tmux.toml'), <<~TOML)
        permission = "plan"
        model = "sonnet"
        rc = true

        [project]
        name = "my-session"
      TOML

      result = load_at(@proj)
      expect(result[:permission]).to eq('plan')
      expect(result[:model]).to eq('sonnet')
      expect(result[:rc]).to be(true)
      expect(result[:project][:name]).to eq('my-session')
    end

    it 'merges the cascade with deeper dirs winning' do
      write(File.join(@home, '.claude-tmux.toml'), %(permission = "plan"\nmodel = "opus"\n))
      write(File.join(@dev, '.claude-tmux.toml'),  %(model = "sonnet"\n))
      write(File.join(@proj, '.claude-tmux.toml'), %(permission = "auto"\n))

      result = load_at(@proj)
      expect(result[:permission]).to eq('auto') # deepest wins
      expect(result[:model]).to eq('sonnet')       # middle wins over shallow
    end

    it 'applies the user-wide config under the dotfile cascade' do
      write(@user_config, %(permission = "accept"\nmodel = "opus"\n))
      write(File.join(@proj, '.claude-tmux.toml'), %(model = "sonnet"\n))

      result = load_at(@proj)
      expect(result[:permission]).to eq('accept')  # only source
      expect(result[:model]).to eq('sonnet') # dotfile overrides user-wide
    end

    it 'raises on an invalid enum value' do
      write(File.join(@proj, '.claude-tmux.toml'), %(permission = "bogus"\n))
      expect { load_at(@proj) }.to raise_error(ClaudeTmux::ConfigError, /permission.*one of/)
    end

    it 'raises on malformed TOML with the file path' do
      write(File.join(@proj, '.claude-tmux.toml'), "not = toml =\n[[[\n")
      expect { load_at(@proj) }.to raise_error(ClaudeTmux::ConfigError, /#{Regexp.escape(@proj)}/)
    end

    it 'warns but does not raise on unknown keys' do
      write(File.join(@proj, '.claude-tmux.toml'), <<~TOML)
        permission = "plan"
        strange = 42
      TOML
      load_at(@proj)
      expect(logger.string).to match(/unknown option 'strange'/)
    end

    it 'does not cross above $HOME' do
      # a sibling of $HOME should never be consulted
      outside = File.expand_path('..', @home)
      write(File.join(outside, '.claude-tmux.toml'), %(permission = "auto"\n))
      result = load_at(@proj)
      expect(result[:permission]).to be_nil
    end
  end
end
