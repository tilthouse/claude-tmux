# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'claude_tmux'
require 'tmpdir'
require 'fileutils'
require 'stringio'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |m|
    m.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)
end

# A test double for ClaudeTmux::Tmux that records calls in memory.
class FakeTmux
  attr_reader :calls, :sessions, :windows

  attr_accessor :global_options

  def initialize(inside: false, existing: [])
    @calls = []
    @sessions = existing.dup
    @windows = Hash.new { |h, k| h[k] = [] }
    @window_options = {}
    @global_options = {}
    @inside = inside
  end

  def show_option_global(option)
    @global_options[option]
  end

  def has_session?(name)
    @calls << [:has_session?, name]
    @sessions.include?(name)
  end

  def inside_tmux?
    @inside
  end

  def new_session_detached(name, cwd, cmd)
    @calls << [:new_session_detached, name, cwd, cmd]
    @sessions << name unless @sessions.include?(name)
    @windows[name] << [0, 'bash']
    true
  end

  def attach(name)
    @calls << [:attach, name]
    nil
  end

  def new_session(name, cwd, cmd)
    @calls << [:new_session, name, cwd, cmd]
    @sessions << name
    nil
  end

  def switch_client(name)
    @calls << [:switch_client, name]
    nil
  end

  def link_window(src, dst)
    @calls << [:link_window, src, dst]
    src_session, = src.split(':', 2)
    @windows[dst] << [@windows[dst].size, src_session.sub(/\Acc-/, '')]
    true
  end

  def rename_window(target, title)
    @calls << [:rename_window, target, title]
    session, idx = target.split(':', 2)
    @windows[session][idx.to_i][1] = title if @windows[session][idx.to_i]
    true
  end

  def kill_window(target)
    @calls << [:kill_window, target]
    session, idx = target.split(':', 2)
    @windows[session]&.delete_at(idx.to_i)
    true
  end

  def kill_session(name)
    @calls << [:kill_session, name]
    @sessions.delete(name)
    true
  end

  def set_option(*args)
    @calls << [:set_option, *args]
    true
  end

  def list_windows(session)
    @windows[session].map { |idx, name| [idx.to_s, name] }
  end

  def list_windows_fmt(session, fields)
    @windows[session].map do |idx, name|
      fields.map do |f|
        case f
        when 'window_index' then idx.to_s
        when 'window_name'  then name
        else                     (@window_options[[session, idx]] || {})[f].to_s
        end
      end
    end
  end

  def set_window_option(window_target, option, value)
    @calls << [:set_window_option, window_target, option, value]
    session, idx = window_target.split(':', 2)
    (@window_options[[session, idx.to_i]] ||= {})[option] = value
    true
  end

  def capture_pane(*)
    ''
  end
end
