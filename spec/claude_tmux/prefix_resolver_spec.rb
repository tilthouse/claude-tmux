# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::PrefixResolver do
  let(:names) { %w[add rm list edit config] }

  describe '.resolve' do
    it 'returns exact matches verbatim' do
      expect(described_class.resolve('add', names)).to eq('add')
    end

    it 'resolves a unique prefix' do
      expect(described_class.resolve('co', names)).to eq('config')
    end

    it 'returns nil when nothing matches' do
      expect(described_class.resolve('zzz', names)).to be_nil
    end

    it 'raises UsageError when the prefix is ambiguous' do
      ambiguous = %w[config configure]
      expect { described_class.resolve('co', ambiguous) }
        .to raise_error(ClaudeTmux::UsageError, /ambiguous: 'co' matches config, configure/)
    end

    it 'prefers an exact match over a longer prefix-match candidate' do
      expect(described_class.resolve('add', %w[add addendum])).to eq('add')
    end
  end
end
