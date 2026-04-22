# frozen_string_literal: true

require 'spec_helper'

# Regression: when tmux is configured with `base-index 1`, source `cc-X`
# sessions create their first window at index 1 (not 0). build_dashboard
# must look up the actual window index instead of hardcoding 0, otherwise
# link_window silently fails and the dashboard ends up empty after the
# kill-windows cleanup pass.
RSpec.describe ClaudeTmux::Group, '#build_dashboard with non-zero base-index sources' do
  it 'links from the source session’s actual first window index, not :0' do
    fake = FakeTmux.new(existing: %w[cc-arni cc-tools])
    # Source sessions have their first window at index 1 (base-index = 1).
    fake.windows['cc-arni'] = [[1, 'shell']]
    fake.windows['cc-tools'] = [[1, 'shell']]

    entries = [
      { session: 'cc-arni',  path: '/tmp/arni',  resolved_flags: [], extra_args: [], from_group: 'projects' },
      { session: 'cc-tools', path: '/tmp/tools', resolved_flags: [], extra_args: [], from_group: 'projects' }
    ]

    group = described_class.new('ccg', [], tmux: fake)
    group.send(:build_dashboard, 'ccg-projects', entries)

    link_calls = fake.calls.select { |c| c.first == :link_window }
    expect(link_calls).to include([:link_window, 'cc-arni:1',  'ccg-projects'])
    expect(link_calls).to include([:link_window, 'cc-tools:1', 'ccg-projects'])
  end
end
