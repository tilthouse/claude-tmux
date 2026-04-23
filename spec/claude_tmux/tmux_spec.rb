# frozen_string_literal: true

require 'spec_helper'

BUNDLER_VARS = %w[
  BUNDLE_GEMFILE
  BUNDLE_BIN_PATH
  BUNDLE_LOCKFILE
  BUNDLER_SETUP
  BUNDLER_VERSION
  RUBYOPT
  GEM_HOME
  GEM_PATH
].freeze

RSpec.describe ClaudeTmux::Tmux do
  subject(:tmux) { described_class.new }

  describe 'bundler env scrubbing' do
    # cct runs under `require "bundler/setup"` when launched from the in-repo
    # bin stub. Simulate that by injecting bundler-style vars into ENV before
    # the spawn and asserting they're gone at the moment tmux is invoked.
    around do |example|
      saved = BUNDLER_VARS.to_h { |k| [k, ENV.fetch(k, nil)] }
      BUNDLER_VARS.each { |k| ENV[k] = "/fake/#{k.downcase}" }
      example.run
    ensure
      BUNDLER_VARS.each { |k| saved&.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
    end

    it '#new_session_detached strips bundler vars from our env before spawning tmux' do
      captured = nil
      allow(tmux).to receive(:system) do |*args|
        # Only capture at the new-session call, not the scrub call.
        next true unless args.include?('new-session')

        captured = BUNDLER_VARS.to_h { |k| [k, ENV.fetch(k, nil)] }
        true
      end

      tmux.new_session_detached('cc-x', '/tmp', ['claude'])

      expect(captured.values.compact).to be_empty
    end

    it '#new_session strips bundler vars from our env before exec-ing tmux' do
      captured = nil
      allow(Kernel).to receive(:send) do |method, *_args|
        raise "unexpected Kernel.send(:#{method})" unless method == :exec

        captured = BUNDLER_VARS.to_h { |k| [k, ENV.fetch(k, nil)] }
        nil
      end

      tmux.new_session('cc-x', '/tmp', ['claude'])

      expect(captured.values.compact).to be_empty
    end

    it '#new_session_detached scrubs bundler vars from the tmux server env first' do
      calls = []
      allow(tmux).to receive(:system) do |*args|
        calls << args
        true
      end

      tmux.new_session_detached('cc-x', '/tmp', ['claude'])

      scrub_idx = calls.index { |c| c.include?('set-environment') }
      new_idx = calls.index { |c| c.include?('new-session') }

      expect(scrub_idx).not_to be_nil
      expect(new_idx).not_to be_nil
      expect(scrub_idx).to be < new_idx
      expect(calls[scrub_idx]).to include('-gu', 'BUNDLE_GEMFILE')
    end
  end
end
