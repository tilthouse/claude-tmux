# frozen_string_literal: true

require 'time'

module ClaudeTmux
  # `claude-tmux project` — per-project launch.
  #
  # 1. Parse CLI options (new OptionParser-driven shape, no bareword presets)
  # 2. Load Options cascade (TOML dotfiles + user-wide config)
  # 3. Merge: CLI wins over dotfile cascade wins over user-wide
  # 4. Compute session name (CLI `-n` > options `[project] name` > git root)
  # 5. Guard `-c`/`-r` against an existing session
  # 6. Attach-or-create `cc-<name>` running `claude` with resolved flags
  class Project
    attr_reader :prog, :argv

    def initialize(prog, argv, tmux: Tmux.new, stderr: $stderr, stdout: $stdout, options_loader: Options)
      @prog = prog
      @argv = argv.dup
      @tmux = tmux
      @stderr = stderr
      @stdout = stdout
      @options_loader = options_loader
    end

    def run
      cli_opts = Parser.new(@prog, @argv).parse
      return print_help if cli_opts[:help]

      dir = resolve_dir(cli_opts)
      defaults = @options_loader.load(dir: dir, logger: @stderr)
      merged = merge(cli_opts, defaults)

      session = SessionName.compute(dir: dir, name: merged[:name])
      guard_resume!(cli_opts, session)

      launch(session, dir, build_claude_flags(cli_opts, merged, session))
    end

    private

    def print_help
      @stdout.puts Help.render(@prog)
      0
    end

    def resolve_dir(cli_opts)
      return Dir.pwd unless cli_opts[:dir]

      path = File.expand_path(cli_opts[:dir])
      raise UsageError, "#{@prog}: not a directory: #{cli_opts[:dir]}" unless File.directory?(path)

      path
    end

    # CLI takes precedence over defaults for every field.
    def merge(cli, defaults)
      {
        permission: cli[:permission] || defaults[:permission],
        model: cli[:model] || defaults[:model],
        yolo: cli[:yolo] || defaults[:yolo],
        rc: cli[:rc] || defaults[:rc],
        name: cli[:name] || defaults.dig(:project, :name)
      }
    end

    def build_claude_flags(cli_opts, merged, session)
      flags = Presets.all_flags(
        permission: merged[:permission],
        model: merged[:model],
        yolo: merged[:yolo]
      )
      flags << '--continue' if cli_opts[:continue]
      if cli_opts[:resume]
        flags << '--resume'
        flags << cli_opts[:resume_id] if cli_opts[:resume_id]
      end
      if merged[:rc]
        ts = Time.now.strftime('%y-%m-%d-%H%M')
        flags += ['--remote-control', '--remote-control-session-name-prefix', "#{session}-#{ts}"]
      end
      flags + cli_opts[:extra_args]
    end

    def guard_resume!(opts, session)
      return unless opts[:continue] || opts[:resume]
      return unless @tmux.has_session?(session)

      flag = opts[:resume] ? '-r' : '-c'
      @stderr.puts "#{@prog}: session '#{session}' already exists; #{flag} only applies when creating a new session."
      @stderr.puts "       Kill it first (tmux kill-session -t '#{session}') or use -n <name> for a concurrent session."
      raise UsageError.new('session already exists', exit_status: 1)
    end

    def launch(session, cwd, flags)
      cmd = ['claude', *flags]
      if @tmux.inside_tmux?
        @tmux.new_session_detached(session, cwd, cmd) unless @tmux.has_session?(session)
        @tmux.switch_client(session)
      elsif @tmux.has_session?(session)
        @tmux.attach(session)
      else
        @tmux.new_session(session, cwd, cmd)
      end
      0
    end
  end
end

require_relative 'project/parser'
require_relative 'project/help'
