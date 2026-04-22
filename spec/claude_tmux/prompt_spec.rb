# frozen_string_literal: true

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
    prompt = described_class.new(responses: [{ method: :input, value: 'typed-name' }])
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
    expect { prompt.choose(%w[a], header: 'h') }.to raise_error(/expected input, got choose/)
  end
end
