# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClaudeTmux::Group, '#build_dashboard' do
  def entry(session, path = "/tmp/#{session.sub(/\Acc-/, '')}")
    { session: session, path: path, resolved_flags: [], extra_args: [], from_group: 'projects' }
  end

  it 'links from the source session’s actual first window index, not :0 (base-index 1)' do
    fake = FakeTmux.new(existing: %w[cc-arni cc-tools])
    fake.windows['cc-arni']  = [[1, 'shell']]
    fake.windows['cc-tools'] = [[1, 'shell']]

    described_class.new('ccg', [], tmux: fake)
                   .send(:build_dashboard, 'ccg-projects', [entry('cc-arni'), entry('cc-tools')])

    link_calls = fake.calls.select { |c| c.first == :link_window }
    expect(link_calls).to include([:link_window, 'cc-arni:1',  'ccg-projects'])
    expect(link_calls).to include([:link_window, 'cc-tools:1', 'ccg-projects'])
  end

  it 'tags each linked window with @ccg-project = <slug> (lets Claude keep the dynamic title)' do
    fake = FakeTmux.new(existing: %w[cc-arni])
    fake.windows['cc-arni'] = [[1, 'shell']]

    described_class.new('ccg', [], tmux: fake)
                   .send(:build_dashboard, 'ccg-projects', [entry('cc-arni')])

    tag_calls = fake.calls.select { |c| c.first == :set_window_option && c[2] == '@ccg-project' }
    expect(tag_calls.map { |c| [c[1], c[3]] }).to include(['ccg-projects:1', 'arni'])
    expect(fake.calls.map(&:first)).not_to include(:rename_window)
  end

  it 'sets per-window window-status-format including the slug token' do
    fake = FakeTmux.new(existing: %w[cc-arni])
    fake.windows['cc-arni'] = [[1, 'shell']]
    # No global format set — fall back to the plain #I <slug> #W default.

    described_class.new('ccg', [], tmux: fake)
                   .send(:build_dashboard, 'ccg-projects', [entry('cc-arni')])

    fmt_calls = fake.calls.select do |c|
      c.first == :set_window_option && %w[window-status-format window-status-current-format].include?(c[2])
    end
    expect(fmt_calls.size).to eq(2) # one of each on the linked window
    fmt_calls.each { |c| expect(c[3]).to include('@ccg-project').and include('#W') }
  end

  it 'splices the slug into a user-themed global format that uses #T (preserves styling)' do
    fake = FakeTmux.new(existing: %w[cc-arni])
    fake.windows['cc-arni'] = [[1, 'shell']]
    themed = '#[fg=blue]#I #[fg=green]#T#[default]'
    fake.global_options['window-status-format'] = themed
    fake.global_options['window-status-current-format'] = themed

    described_class.new('ccg', [], tmux: fake)
                   .send(:build_dashboard, 'ccg-projects', [entry('cc-arni')])

    set_window_fmt = fake.calls.find { |c| c.first == :set_window_option && c[2] == 'window-status-format' }
    expect(set_window_fmt[3]).to include('#[fg=blue]').and include('#[fg=green]')
    expect(set_window_fmt[3]).to include('@ccg-project')
    # Slug appears immediately before #T (the title token), so styling stays intact.
    expect(set_window_fmt[3]).to match(/@ccg-project[^#]*#T/)
  end

  it 'kills windows whose @ccg-project tag is missing or stale' do
    # Simulate a re-run: dashboard already has [arni, stale], but the new entries are [arni, tools].
    fake = FakeTmux.new(existing: %w[cc-arni cc-tools ccg-projects])
    fake.windows['cc-arni']  = [[1, 'shell']]
    fake.windows['cc-tools'] = [[1, 'shell']]
    fake.windows['ccg-projects'] = [[0, 'arni-win'], [1, 'stale-win']]
    fake.set_window_option('ccg-projects:0', '@ccg-project', 'arni')
    fake.set_window_option('ccg-projects:1', '@ccg-project', 'something-removed')

    described_class.new('ccg', [], tmux: fake)
                   .send(:build_dashboard, 'ccg-projects', [entry('cc-arni'), entry('cc-tools')])

    kill_calls = fake.calls.select { |c| c.first == :kill_window }
    # The stale window (no longer in entries) should be killed; arni stays.
    expect(kill_calls).to include([:kill_window, 'ccg-projects:1'])
    expect(kill_calls).not_to include([:kill_window, 'ccg-projects:0'])
  end
end
