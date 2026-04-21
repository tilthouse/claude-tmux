# frozen_string_literal: true

require_relative 'lib/claude_tmux/version'

Gem::Specification.new do |spec|
  spec.name          = 'claude-tmux'
  spec.version       = ClaudeTmux::VERSION
  spec.authors       = ['Alex Boster']
  spec.email         = ['boster@tilthouse.org']

  spec.summary       = 'Per-project tmux session launcher for Claude Code, with group mode and a decorated picker.'
  spec.description   = <<~DESC
    claude-tmux (cct) launches or attaches a per-project tmux session running
    Claude Code. ccg launches a group of projects into one tmux session with
    one window per project. sesh-pick decorates sesh's fzf picker with
    per-session Claude state glyphs.
  DESC
  spec.homepage      = 'https://github.com/tilthouse/claude-tmux'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir[
    'lib/**/*.rb',
    'bin/*',
    'README.md',
    'CHANGELOG.md',
    'LICENSE'
  ]

  spec.bindir      = 'bin'
  spec.executables = %w[claude-tmux cct ccg ccs]

  spec.add_dependency 'toml-rb', '~> 2.2'

  spec.add_development_dependency 'rake',     '~> 13.0'
  spec.add_development_dependency 'rspec',    '~> 3.13'
  spec.add_development_dependency 'rubocop',  '~> 1.68'
end
