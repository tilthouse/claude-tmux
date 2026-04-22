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

  it 'creates a new group via [+ new group] then exits saving' do
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[+ new group]' } },
                                          { method: :input,   value: 'mornings' },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group_names).to eq(['mornings'])
    expect(reloaded.group('mornings').entries).to be_empty
  end

  it 'shows group_view with entries and returns to groups_list on ESC' do
    cfg_with('work' => ['~/x', '~/y']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose, value: { key: nil, item: '[work] (2 projects)' } },
                                          { method: :choose, value: { key: nil, item: nil } },
                                          { method: :choose, value: { key: nil, item: nil } }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    expect(tui.run).to eq(0)
  end

  it 'removes an entry via action_menu and saves on exit' do
    cfg_with('work' => ['~/x', '~/y']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[work] (2 projects)' } },
                                          { method: :choose,  value: { key: nil, item: '~/x' } },
                                          { method: :choose,  value: { key: nil, item: 'Remove' } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('work').entries.map(&:path)).to eq(['~/y'])
  end

  it 'moves an entry up via action_menu' do
    cfg_with('g' => ['~/a', '~/b', '~/c']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[g] (3 projects)' } },
                                          { method: :choose,  value: { key: nil, item: '~/c' } },
                                          { method: :choose,  value: { key: nil, item: 'Move up' } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('g').entries.map(&:path)).to eq(%w[~/a ~/c ~/b])
  end
end
