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
    groups.each do |name, paths|
      if paths.empty?
        cfg.create_empty_group(name)
      else
        paths.each { |p| cfg.add_entry(name, p) }
      end
    end
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

  it 'renames a group via R hotkey' do
    cfg_with('work' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[work] (1 project)' } },
                                          { method: :choose,  value: { key: 'R', item: nil } },
                                          { method: :input,   value: 'office' },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group_names).to eq(['office'])
  end

  it 'deletes a group via D hotkey when confirmed' do
    cfg_with('work' => ['~/x'], 'life' => ['~/y']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[work] (1 project)' } },
                                          { method: :choose,  value: { key: 'D', item: nil } },
                                          { method: :confirm, value: true },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group_names).to eq(['life'])
  end

  it 'adds a candidate-list entry to the group' do
    cfg_with('work' => [], 'life' => ['~/elsewhere']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[work] (0 projects)' } },
                                          { method: :choose,  value: { key: nil, item: '[+ add entry]' } },
                                          { method: :choose,  value: { key: nil, item: "[group:life]\t~/elsewhere", query: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('work').entries.map(&:path)).to eq(['~/elsewhere'])
  end

  it 'adds an ad-hoc typed path when no row matches and the query is path-shaped' do
    cfg_with('work' => []).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[work] (0 projects)' } },
                                          { method: :choose,  value: { key: nil, item: '[+ add entry]' } },
                                          { method: :choose,  value: { key: nil, item: nil, query: '~/typed' } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('work').entries.map(&:path)).to eq(['~/typed'])
  end

  it 'edits per-entry presets via three sequential prompts' do
    cfg_with('g' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose, value: { key: nil, item: '[g] (1 project)' } },
                                          { method: :choose, value: { key: nil, item: '~/x' } },
                                          { method: :choose, value: { key: nil, item: 'Edit presets' } },
                                          { method: :choose, value: { key: nil, item: 'plan' } },
                                          { method: :choose, value: { key: nil, item: 'sonnet' } },
                                          { method: :choose, value: { key: nil, item: 'off' } },
                                          { method: :choose, value: { key: nil, item: nil } },
                                          { method: :choose, value: { key: nil, item: nil } },
                                          { method: :confirm, value: true }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    reloaded = ClaudeTmux::Config.load(path: @path)
    expect(reloaded.group('g').entries.first.presets).to eq(%w[plan sonnet])
  end

  it 'aborts preset edit on ESC at any step (snapshot untouched)' do
    cfg_with('g' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose, value: { key: nil, item: '[g] (1 project)' } },
                                          { method: :choose, value: { key: nil, item: '~/x' } },
                                          { method: :choose, value: { key: nil, item: 'Edit presets' } },
                                          { method: :choose, value: { key: nil, item: 'plan' } },
                                          { method: :choose, value: { key: nil, item: nil } },
                                          { method: :choose, value: { key: nil, item: nil } },
                                          { method: :choose, value: { key: nil, item: nil } }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    expect(ClaudeTmux::Config.load(path: @path).group('g').entries.first.presets).to eq([])
  end

  it 'cancels delete when not confirmed' do
    cfg_with('work' => ['~/x']).save
    prompt = ClaudeTmux::FakePrompt.new(responses: [
                                          { method: :choose,  value: { key: nil, item: '[work] (1 project)' } },
                                          { method: :choose,  value: { key: 'D', item: nil } },
                                          { method: :confirm, value: false },
                                          { method: :choose,  value: { key: nil, item: nil } },
                                          { method: :choose,  value: { key: nil, item: nil } }
                                        ])
    tui = described_class.new(config_path: @path, prompt: prompt)
    tui.run
    expect(ClaudeTmux::Config.load(path: @path).group_names).to eq(['work'])
  end
end
