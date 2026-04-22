# frozen_string_literal: true

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

  it 'resolves `a` to `add`' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)

      group = described_class.new('ccg', ['a', 'newgroup', '/tmp'], stderr: stderr, stdout: stdout)
      group.run
      expect(stdout.string).to include('Added')
      expect(File.read(conf)).to include('[newgroup]')
    end
  end

  it 'routes `ccg config` to ConfigTui' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      File.write(conf, "[work]\n~/x\n")
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)
      fake = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose, value: { key: nil, item: nil } }
                                        ])
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

  it 'lets unknown bareword fall through to launch path (existing classifier)' do
    Dir.mktmpdir do |dir|
      conf = File.join(dir, 'groups.conf')
      File.write(conf, "[work]\n~/x\n")
      stub_const('ClaudeTmux::Config::DEFAULT_PATH', conf)

      group = described_class.new('ccg', %w[zzz], stderr: stderr, stdout: stdout)
      # Group#run does not catch UsageError; CLI does. Direct .run lets it bubble.
      expect { group.run }.to raise_error(ClaudeTmux::UsageError, /unknown argument 'zzz'/)
    end
  end
end
