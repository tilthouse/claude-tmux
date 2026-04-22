# frozen_string_literal: true

module ClaudeTmux
  # Dispatches on invocation name ($0) and, for `claude-tmux`, the first
  # positional argument:
  #
  #   cct ARGS         → Project
  #   ccg ARGS         → Group
  #   ccs ARGS         → Picker
  #   claude-tmux                   → print top-level help
  #   claude-tmux project ARGS      → Project
  #   claude-tmux group ARGS        → Group
  #   claude-tmux sess-pick ARGS    → Picker (canonical)
  #   claude-tmux pick ARGS         → Picker (alias)
  class CLI
    SYMLINK_MAP = {
      'cct' => :project,
      'ccg' => :group,
      'ccs' => :picker
    }.freeze

    SUBCOMMANDS = {
      'project' => :project,
      'group' => :group,
      'pick' => :picker,
      'sess-pick' => :picker
    }.freeze

    SILENT_USAGE_MESSAGES = [
      'session already exists',
      'resume/continue in group mode',
      'no projects'
    ].freeze

    SHORTCUT_NAMES = { project: 'cct', group: 'ccg', picker: 'ccs' }.freeze

    def initialize(prog_path, argv, stderr: $stderr, stdout: $stdout)
      @prog_path = prog_path
      @prog = File.basename(prog_path)
      @argv = argv.dup
      @stderr = stderr
      @stdout = stdout
    end

    def run
      dispatch
    rescue UsageError => e
      @stderr.puts e.message unless e.message.nil? || e.message.empty? || SILENT_USAGE_MESSAGES.include?(e.message)
      e.exit_status
    end

    private

    def dispatch
      if (target = SYMLINK_MAP[@prog])
        return run_target(target, @prog, @argv)
      end

      # Canonical 'claude-tmux' invocation.
      if @argv.empty? || %w[-h --help].include?(@argv.first)
        @stdout.puts top_level_help
        return 0
      end

      sub = @argv.first
      resolved = PrefixResolver.resolve(sub, SUBCOMMANDS.keys)
      target = SUBCOMMANDS[resolved] if resolved
      unless target
        @stderr.puts "#{@prog}: unknown subcommand '#{sub}'"
        @stderr.puts top_level_help
        return 2
      end

      shortcut_prog = shortcut_for(target)
      run_target(target, shortcut_prog, @argv[1..])
    end

    def run_target(target, prog, args)
      case target
      when :project then Project.new(prog, args, stderr: @stderr, stdout: @stdout).run
      when :group   then Group.new(prog, args, stderr: @stderr, stdout: @stdout).run
      when :picker  then Picker.new(stderr: @stderr, stdout: @stdout).run
      end
    end

    def shortcut_for(target)
      SHORTCUT_NAMES[target]
    end

    def top_level_help
      <<~HELP
        claude-tmux #{VERSION} — tmux session launcher for Claude Code.

        USAGE
          claude-tmux <subcommand> [args...]

        SUBCOMMANDS
          project [OPTIONS] [DIR]        Launch/attach cc-<name> for a project.
                                         Shortcut: cct
          group [OPTIONS] [GROUP|PATH]…  Launch a group of projects in one tmux session.
                                         Shortcut: ccg
            group add <name> <path>      Add an entry to a named group.
            group rm <name> [<path>]     Remove an entry, or delete the group.
            group list [<name>]          List groups, or dump one group's entries.
            group edit                   Open groups.conf in $EDITOR.
          sess-pick                      Decorated sesh session picker.
                                         Shortcut: ccs
          pick                           Alias of sess-pick.

        GLOBAL
          -h, --help   Show help (subcommand-specific if after a subcommand).

        Run `<subcommand> --help` (e.g. `cct --help`) for details.
      HELP
    end
  end
end
