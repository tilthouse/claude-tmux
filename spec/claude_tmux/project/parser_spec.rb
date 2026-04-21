# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Project::Parser do
  def parse(*argv)
    described_class.new('cct', argv).parse
  end

  it 'defaults to empty opts' do
    opts = parse
    expect(opts[:permission]).to be_nil
    expect(opts[:model]).to be_nil
    expect(opts[:yolo]).to be(false)
    expect(opts[:rc]).to be(false)
    expect(opts[:continue]).to be(false)
    expect(opts[:resume]).to be(false)
    expect(opts[:dir]).to be_nil
    expect(opts[:extra_args]).to be_empty
  end

  it 'accepts -p and -m' do
    opts = parse('-p', 'plan', '-m', 'sonnet')
    expect(opts[:permission]).to eq('plan')
    expect(opts[:model]).to eq('sonnet')
  end

  it 'accepts long forms' do
    opts = parse('--permission', 'auto', '--model', 'opus')
    expect(opts[:permission]).to eq('auto')
    expect(opts[:model]).to eq('opus')
  end

  it 'rejects invalid permission and model values' do
    expect { parse('-p', 'bogus') }.to raise_error(ClaudeTmux::UsageError)
    expect { parse('-m', 'haiku') }.to raise_error(ClaudeTmux::UsageError)
  end

  it 'marks --yolo and --rc' do
    expect(parse('--yolo')[:yolo]).to be(true)
    expect(parse('--rc')[:rc]).to be(true)
  end

  it 'accepts an optional resume id' do
    expect(parse('-r', '7f3a')).to include(resume: true, resume_id: '7f3a')
    expect(parse('-r')).to include(resume: true, resume_id: nil)
  end

  it 'rejects -r combined with -c' do
    expect { parse('-c', '-r') }.to raise_error(ClaudeTmux::UsageError, /mutually exclusive/)
  end

  it 'accepts -n' do
    expect(parse('-n', 'scratch')[:name]).to eq('scratch')
  end

  it 'accepts an optional DIR positional' do
    expect(parse('~/projA')[:dir]).to eq('~/projA')
  end

  it 'rejects two or more positionals' do
    expect { parse('~/a', '~/b') }.to raise_error(ClaudeTmux::UsageError, /too many positional/)
  end

  it 'passes everything after -- to extra_args' do
    opts = parse('-p', 'plan', '--', '--add-dir', '../sibling')
    expect(opts[:permission]).to eq('plan')
    expect(opts[:extra_args]).to eq(['--add-dir', '../sibling'])
  end
end
