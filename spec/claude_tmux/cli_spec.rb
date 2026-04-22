# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::CLI do
  let(:stderr) { StringIO.new }
  let(:stdout) { StringIO.new }

  it 'resolves a unique top-level subcommand prefix to the right target' do
    fake_picker = instance_double(ClaudeTmux::Picker, run: 0)
    allow(ClaudeTmux::Picker).to receive(:new).and_return(fake_picker)

    cli = described_class.new('claude-tmux', %w[pi], stderr: stderr, stdout: stdout)
    expect(cli.run).to eq(0)
    expect(ClaudeTmux::Picker).to have_received(:new)
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
