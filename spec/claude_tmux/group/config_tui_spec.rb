# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Group::ConfigTui do
  around do |ex|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, 'groups.conf')
      ex.run
    end
  end

  def cfg_with(groups)
    cfg = ClaudeTmux::Config.new(path: @path)
    groups.each { |name, paths| paths.each { |p| cfg.add_entry(name, p) } }
    cfg
  end

  it 'opens groups_list and exits cleanly on ESC with no save when clean' do
    cfg = cfg_with('work' => ['~/x'])
    cfg.save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose, value: { key: nil, item: nil, query: nil } }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    expect(tui.run).to eq(0)
    expect(prompt.log.size).to eq(1)
  end
end
