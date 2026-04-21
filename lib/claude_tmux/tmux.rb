# frozen_string_literal: true

module ClaudeTmux
  # Thin wrapper around the tmux CLI. All methods that take a session/window
  # name pass tmux argv as discrete tokens (no shell interpolation), so these
  # are safe against shell injection even for user-controlled names.
  #
  # Methods that replace the current process (attach / new-session /
  # switch-client) call Kernel#exec, which under multiple-argument form
  # performs a direct execve(2) with no shell involvement.
  class Tmux
    def has_session?(name)
      system('tmux', 'has-session', '-t', name, out: File::NULL, err: File::NULL)
    end

    def inside_tmux?
      ENV.fetch('TMUX', nil) && !ENV['TMUX'].empty?
    end

    def new_session_detached(name, cwd, command)
      system('tmux', 'new-session', '-d', '-s', name, '-c', cwd, *command)
    end

    def attach(name)
      Kernel.send(:exec, 'tmux', 'attach', '-t', name)
    end

    def new_session(name, cwd, command)
      Kernel.send(:exec, 'tmux', 'new-session', '-s', name, '-c', cwd, *command)
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
  end
end
