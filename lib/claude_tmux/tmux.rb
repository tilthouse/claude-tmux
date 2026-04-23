# frozen_string_literal: true

require 'bundler'

module ClaudeTmux
  # Thin wrapper around the tmux CLI. All methods that take a session/window
  # name pass tmux argv as discrete tokens (no shell interpolation), so these
  # are safe against shell injection even for user-controlled names.
  #
  # Methods that replace the current process (attach / new-session /
  # switch-client) call Kernel#exec, which under multiple-argument form
  # performs a direct execve(2) with no shell involvement.
  #
  # When cct is launched via its in-repo bin stub, bundler sets
  # BUNDLE_GEMFILE / RUBYOPT / GEM_HOME / etc. in our process. Without
  # scrubbing, tmux — and the child `claude` it spawns — inherits this gem's
  # bundle context, so any ruby/bundle/rspec run inside the Claude Code
  # session resolves against our Gemfile instead of the project's.
  #
  # Two mechanisms cover the two cases this can happen in:
  #
  #   * `Bundler.with_unbundled_env` around new-session — if our invocation
  #     is what starts the tmux server, the server inherits the scrubbed env.
  #   * `tmux set-environment -gu` per injected var — if a server is already
  #     running (started earlier under bundler, before this fix), its global
  #     env is already contaminated; the client has to remove each var
  #     explicitly. Silently no-ops if no server exists.
  class Tmux
    def has_session?(name)
      system('tmux', 'has-session', '-t', name, out: File::NULL, err: File::NULL)
    end

    def inside_tmux?
      ENV.fetch('TMUX', nil) && !ENV['TMUX'].empty?
    end

    def new_session_detached(name, cwd, command)
      scrub_bundler_from_server
      Bundler.with_unbundled_env do
        system('tmux', 'new-session', '-d', '-s', name, '-c', cwd, *command)
      end
    end

    def attach(name)
      Kernel.send(:exec, 'tmux', 'attach', '-t', name)
    end

    def new_session(name, cwd, command)
      scrub_bundler_from_server
      Bundler.with_unbundled_env do
        Kernel.send(:exec, 'tmux', 'new-session', '-s', name, '-c', cwd, *command)
      end
    end

    def switch_client(name)
      Kernel.send(:exec, 'tmux', 'switch-client', '-t', name)
    end

    def link_window(src_target, dst_session)
      system('tmux', 'link-window', '-s', src_target, '-t', dst_session,
             out: File::NULL, err: File::NULL)
    end

    def rename_window(target, title)
      system('tmux', 'rename-window', '-t', target, title,
             out: File::NULL, err: File::NULL)
    end

    def kill_window(target)
      system('tmux', 'kill-window', '-t', target,
             out: File::NULL, err: File::NULL)
    end

    def kill_session(name)
      system('tmux', 'kill-session', '-t', name,
             out: File::NULL, err: File::NULL)
    end

    def set_option(session, option, value)
      system('tmux', 'set-option', '-t', session, option, value,
             out: File::NULL, err: File::NULL)
    end

    def set_window_option(window_target, option, value)
      system('tmux', 'set-window-option', '-t', window_target, option, value,
             out: File::NULL, err: File::NULL)
    end

    # Returns the global value of a tmux option, or nil if unset.
    def show_option_global(option)
      out = IO.popen(['tmux', 'show-options', '-gv', option, err: File::NULL], &:read) || ''
      out.empty? ? nil : out.chomp
    end

    # list-windows with arbitrary tmux format fields. Returns an Array of Arrays;
    # the inner array has one element per requested field, in order.
    def list_windows_fmt(session, fields)
      fmt = fields.map { |f| "\#{#{f}}" }.join("\t")
      out = IO.popen(['tmux', 'list-windows', '-t', session, '-F', fmt, err: File::NULL], &:read) || ''
      out.each_line.map { |line| line.chomp.split("\t", fields.size) }
    end

    def capture_pane(target, lines: 30)
      IO.popen(['tmux', 'capture-pane', '-pt', target, '-S', "-#{lines}", err: File::NULL], &:read) || ''
    rescue Errno::ENOENT, Errno::EPIPE
      ''
    end

    def list_windows(session)
      fmt = '#{window_index} #{window_name}' # rubocop:disable Lint/InterpolationCheck
      out = IO.popen(['tmux', 'list-windows', '-t', session, '-F', fmt, err: File::NULL], &:read) || ''
      out.each_line.map { |line| line.chomp.split(' ', 2) }
    end

    private

    def scrub_bundler_from_server
      return if bundler_injected_keys.empty?

      argv = ['tmux']
      bundler_injected_keys.each_with_index do |var, i|
        argv << ';' unless i.zero?
        argv.push('set-environment', '-gu', var)
      end
      system(*argv, out: File::NULL, err: File::NULL)
    end

    def bundler_injected_keys
      @bundler_injected_keys ||= (ENV.to_h.keys - Bundler.unbundled_env.keys).freeze
    end
  end
end
