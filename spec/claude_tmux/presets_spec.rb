# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Presets do
  describe '.permission_flags' do
    it('maps plan')   { expect(described_class.permission_flags('plan')).to eq(['--permission-mode', 'plan']) }
    it('maps auto')   { expect(described_class.permission_flags('auto')).to eq(['--permission-mode', 'auto']) }
    it('maps accept') { expect(described_class.permission_flags('accept')).to eq(['--permission-mode', 'acceptEdits']) }
    it('nil returns empty') { expect(described_class.permission_flags(nil)).to eq([]) }

    it 'raises on invalid' do
      expect { described_class.permission_flags('nope') }.to raise_error(ArgumentError)
    end
  end

  describe '.model_flags' do
    it { expect(described_class.model_flags('opus')).to eq(['--model', 'opus']) }
    it { expect(described_class.model_flags('sonnet')).to eq(['--model', 'sonnet']) }
    it { expect(described_class.model_flags(nil)).to eq([]) }

    it 'raises on invalid' do
      expect { described_class.model_flags('haiku') }.to raise_error(ArgumentError)
    end
  end

  describe '.yolo_flags' do
    it { expect(described_class.yolo_flags(true)).to eq(['--dangerously-skip-permissions']) }
    it { expect(described_class.yolo_flags(false)).to eq([]) }
  end

  describe '.all_flags' do
    it 'concatenates' do
      expect(described_class.all_flags(permission: 'plan', model: 'sonnet', yolo: false))
        .to eq(['--permission-mode', 'plan', '--model', 'sonnet'])
    end

    it 'skips nils' do
      expect(described_class.all_flags(permission: nil, model: nil, yolo: true))
        .to eq(['--dangerously-skip-permissions'])
    end
  end
end
