# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Project do
  let(:tmux) { FakeTmux.new(inside: false) }
  let(:stderr) { StringIO.new }
  let(:stdout) { StringIO.new }

  # Stub Options.load so specs don't read the user's real config.
  let(:fake_defaults) do
    {
      permission: nil,
      model: nil,
      yolo: false,
      rc: false,
      project: { name: nil },
      group: { label: nil }
    }
  end

  let(:options_loader) do
    defaults = fake_defaults # capture into a local so the singleton block can close over it
    loader = Class.new
    loader.define_singleton_method(:load) { |**_| defaults }
    loader
  end

  def run(argv, session_name: 'cc-myproj')
    allow(ClaudeTmux::SessionName).to receive(:compute).and_return(session_name)
    described_class.new('cct', argv,
                        tmux: tmux, stderr: stderr, stdout: stdout,
                        options_loader: options_loader).run
  end

  it 'creates a new session outside tmux' do
    run([])
    expect(tmux.calls).to include([:new_session, 'cc-myproj', Dir.pwd, ['claude']])
  end

  it 'attaches when a session already exists' do
    tmux.sessions << 'cc-myproj'
    run([])
    expect(tmux.calls).to include([:attach, 'cc-myproj'])
  end

  it 'creates detached + switch-client inside tmux' do
    t = FakeTmux.new(inside: true)
    allow(ClaudeTmux::SessionName).to receive(:compute).and_return('cc-myproj')
    described_class.new('cct', [], tmux: t, stderr: stderr, stdout: stdout,
                                   options_loader: options_loader).run
    expect(t.calls.any? { |c| c.first == :new_session_detached }).to be(true)
    expect(t.calls.last).to eq([:switch_client, 'cc-myproj'])
  end

  it 'passes CLI option flags on create' do
    run(%w[-p plan -m sonnet])
    create = tmux.calls.find { |c| c.first == :new_session }
    expect(create.last).to eq(['claude', '--permission-mode', 'plan', '--model', 'sonnet'])
  end

  it 'attaches RC flags with a timestamped prefix, tmux name unchanged' do
    run(%w[--rc])
    create = tmux.calls.find { |c| c.first == :new_session }
    expect(create[1]).to eq('cc-myproj')
    cmd = create.last
    expect(cmd).to include('--remote-control')
    prefix_idx = cmd.index('--remote-control-session-name-prefix')
    expect(cmd[prefix_idx + 1]).to match(/\Acc-myproj-\d{2}-\d{2}-\d{2}-\d{4}\z/)
  end

  it 'errors on -c when the session already exists' do
    tmux.sessions << 'cc-myproj'
    expect { run(%w[-c]) }.to raise_error(ClaudeTmux::UsageError)
    expect(stderr.string).to match(/only applies when creating a new session/)
  end

  it 'passes --continue on create' do
    run(%w[-c])
    create = tmux.calls.find { |c| c.first == :new_session }
    expect(create.last).to include('--continue')
  end

  it 'picks up dotfile defaults and lets CLI override' do
    fake_defaults[:permission] = 'plan'
    fake_defaults[:model] = 'opus'
    run(%w[-m sonnet])
    create = tmux.calls.find { |c| c.first == :new_session }
    cmd = create.last
    expect(cmd).to include('--permission-mode', 'plan') # from dotfile
    expect(cmd).to include('--model', 'sonnet') # CLI override
  end

  it 'passes --yolo when the dotfile sets it' do
    fake_defaults[:yolo] = true
    run([])
    create = tmux.calls.find { |c| c.first == :new_session }
    expect(create.last).to include('--dangerously-skip-permissions')
  end
end
