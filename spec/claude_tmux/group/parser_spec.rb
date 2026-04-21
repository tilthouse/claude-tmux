# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Group::Parser do
  let(:config) do
    c = ClaudeTmux::Config.new(path: '/dev/null')
    c.add_entry('morning', '~/Developer/a')
    c.add_entry('evening', '~/Developer/b')
    c
  end

  def parse(*argv)
    described_class.new('ccg', argv, config: config).parse
  end

  it 'recognizes named groups from the config' do
    expect(parse('morning')[:named_groups]).to eq(['morning'])
  end

  it 'accepts multiple named groups as a union' do
    expect(parse('morning', 'evening')[:named_groups]).to eq(%w[morning evening])
  end

  it 'treats pathlike tokens as ad-hoc paths' do
    opts = parse('~/projA', './projB', '/abs/projC')
    expect(opts[:ad_hoc_paths]).to eq(['~/projA', './projB', '/abs/projC'])
  end

  it 'combines named group with extras' do
    opts = parse('morning', '~/extra')
    expect(opts[:named_groups]).to eq(['morning'])
    expect(opts[:ad_hoc_paths]).to eq(['~/extra'])
  end

  it 'rejects preset words as barewords (they are options now)' do
    expect { parse('plan') }.to raise_error(ClaudeTmux::UsageError, /unknown argument/)
  end

  it 'rejects unknown barewords with a helpful message' do
    expect { parse('nonexistent') }
      .to raise_error(ClaudeTmux::UsageError, /unknown argument.*groups\.conf/)
  end

  it 'accepts -n label override' do
    expect(parse('morning', '-n', 'work')[:label_override]).to eq('work')
  end

  it 'accepts -p, -m, --yolo as defaults' do
    opts = parse('morning', '-p', 'plan', '-m', 'sonnet', '--yolo')
    expect(opts[:permission]).to eq('plan')
    expect(opts[:model]).to eq('sonnet')
    expect(opts[:yolo]).to be(true)
  end

  it 'rejects invalid permission/model values' do
    expect { parse('-p', 'bogus') }.to raise_error(ClaudeTmux::UsageError)
    expect { parse('-m', 'haiku') }.to raise_error(ClaudeTmux::UsageError)
  end

  it 'sets rc/continue/resume flags' do
    expect(parse('morning', '--rc')[:rc]).to be(true)
    expect(parse('morning', '-c')[:continue]).to be(true)
    expect(parse('morning', '-r')[:resume]).to be(true)
  end

  it 'passes everything after -- to extra_args' do
    opts = parse('morning', '--', '--add-dir', 'x')
    expect(opts[:extra_args]).to eq(['--add-dir', 'x'])
  end
end
