# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Group::ConfigTui::CandidateBuilder do
  around do |ex|
    Dir.mktmpdir do |home|
      @home = home
      @dev = File.join(home, 'Developer')
      FileUtils.mkdir_p(@dev)
      ex.run
    end
  end

  def make_dir(*parts)
    path = File.join(@dev, *parts)
    FileUtils.mkdir_p(path)
    path
  end

  def make_repo(*parts)
    path = make_dir(*parts)
    FileUtils.mkdir_p(File.join(path, '.git'))
    path
  end

  def cfg_with(groups)
    cfg = ClaudeTmux::Config.new(path: '/dev/null')
    groups.each do |name, paths|
      paths.each { |p| cfg.add_entry(name, p) }
    end
    cfg
  end

  it 'lists entries from other groups first, tagged [group:NAME]' do
    cfg = cfg_with('work' => ['~/x'], 'life' => ['~/y'])
    builder = described_class.new(config: cfg, current_group: 'work', sesh: -> { [] }, dev_root: @dev)
    rows = builder.build
    expect(rows.first).to include(tag: '[group:life]', path: '~/y')
  end

  it 'omits entries already in the current group' do
    cfg = cfg_with('work' => ['~/x'])
    builder = described_class.new(config: cfg, current_group: 'work', sesh: -> { [] }, dev_root: @dev)
    expect(builder.build.map { |r| r[:path] }).not_to include('~/x')
  end

  it 'includes sesh entries tagged [sesh]' do
    builder = described_class.new(
      config: cfg_with({}), current_group: 'work',
      sesh: -> { ['/tmp/seshy'] }, dev_root: @dev
    )
    rows = builder.build
    expect(rows.find { |r| r[:tag] == '[sesh]' }[:path]).to eq('/tmp/seshy')
  end

  it 'walks dev_root depth-first for .git dirs, tagged [dev]' do
    make_repo('tools', 'projA')
    make_repo('clients', 'projB')
    make_dir('not-a-repo')
    builder = described_class.new(
      config: cfg_with({}), current_group: 'work',
      sesh: -> { [] }, dev_root: @dev
    )
    paths = builder.build.select { |r| r[:tag] == '[dev]' }.map { |r| r[:path] }
    expect(paths).to include(File.join(@dev, 'clients', 'projB'), File.join(@dev, 'tools', 'projA'))
    expect(paths).not_to include(File.join(@dev, 'not-a-repo'))
    expect(paths.index(File.join(@dev, 'clients', 'projB')))
      .to be < paths.index(File.join(@dev, 'tools', 'projA'))
  end

  it 'dedups by canonical path, keeping first occurrence' do
    cfg = cfg_with('life' => ['/tmp/dup'])
    builder = described_class.new(
      config: cfg, current_group: 'work',
      sesh: -> { ['/tmp/dup'] }, dev_root: @dev
    )
    rows = builder.build
    dup_rows = rows.select { |r| r[:path] == '/tmp/dup' }
    expect(dup_rows.size).to eq(1)
    expect(dup_rows.first[:tag]).to eq('[group:life]')
  end

  it 'caps total candidates at the limit' do
    100.times { |i| make_repo('many', "p#{format('%03d', i)}") }
    builder = described_class.new(
      config: cfg_with({}), current_group: 'work',
      sesh: -> { [] }, dev_root: @dev, limit: 50
    )
    expect(builder.build.size).to eq(50)
  end

  it 'silently skips dev walk if dev_root does not exist' do
    builder = described_class.new(
      config: cfg_with({}), current_group: 'work',
      sesh: -> { [] }, dev_root: '/nonexistent'
    )
    expect(builder.build).to eq([])
  end
end
