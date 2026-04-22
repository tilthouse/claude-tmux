# frozen_string_literal: true

require 'time'

module ClaudeTmux
  # `claude-tmux group` — multi-project launch. Creates or attaches a
  # grouping tmux session `ccg-<label>` with one window per project,
  # each window linked from the project's `cc-<name>` source session.
  #
  # Per-source sessions keep their plain identity and are still reachable
  # via `cct` in their repo. Killing the grouping session does not kill
  # sources; killing a source's claude closes both windows naturally.
  class Group
    DASHBOARD_PREFIX     = 'ccg-'
    RESERVED_SUBCOMMANDS = %w[add rm list edit].freeze

    attr_reader :prog, :argv

    def initialize(prog, argv,
                   tmux: Tmux.new, config: nil, options_loader: Options,
                   stderr: $stderr, stdout: $stdout)
      @prog = prog
      @argv = argv.dup
      @tmux = tmux
      @config = config
      @options_loader = options_loader
      @stderr = stderr
      @stdout = stdout
    end

    def run
      return print_help if %w[-h --help help].include?(@argv.first)

      return run_management(@argv.shift) if @argv.first && RESERVED_SUBCOMMANDS.include?(@argv.first)

      run_launch
    end

    private

    def config
      @config ||= Config.load
    end

    def print_help
      @stdout.puts Help.render(@prog)
      0
    end

    # ---- management subcommands -------------------------------------------

    def run_management(cmd)
      case cmd
      when 'add'  then cmd_add(@argv)
      when 'rm'   then cmd_rm(@argv)
      when 'list' then cmd_list(@argv)
      when 'edit' then cmd_edit
      end
    end

    def cmd_add(args)
      opts, positional = ManagementParser.new(@prog, args).parse
      raise UsageError, "#{@prog}: usage: #{@prog} add <group> <path> [options]" if positional.size < 2

      group, path, = positional
      path = Dir.pwd if path == '.'
      presets = presets_from_opts(opts)
      Config.load.tap do |c|
        c.add_entry(group, c.canonicalize_path(path), presets)
        c.save
        msg = "Added #{c.canonicalize_path(path)}"
        msg += " (#{presets.join(' ')})" unless presets.empty?
        msg += " to [#{group}]"
        @stdout.puts msg
      end
      0
    rescue ConfigError => e
      @stderr.puts "#{@prog}: #{e.message}"
      1
    end

    def cmd_rm(args)
      raise UsageError, "#{@prog}: usage: #{@prog} rm <group> [<path>]" if args.empty?

      group = args.shift
      path = args.shift
      c = Config.load
      unless c.group?(group)
        @stderr.puts "#{@prog}: no such group: #{group}"
        return 1
      end

      if path
        path = Dir.pwd if path == '.'
        if c.remove_entry(group, c.canonicalize_path(path))
          c.save
          @stdout.puts "Removed #{path} from [#{group}]"
          0
        else
          @stderr.puts "#{@prog}: #{path} not found in [#{group}]"
          1
        end
      else
        c.delete_group(group)
        c.save
        @stdout.puts "Deleted group [#{group}]"
        0
      end
    end

    def cmd_list(args)
      c = Config.load
      if args.empty?
        if c.groups.empty?
          @stdout.puts '(no groups configured)'
          return 0
        end
        c.groups.each do |g|
          @stdout.puts "[#{g.name}] (#{g.entries.size} project#{'s' if g.entries.size != 1})"
          g.entries.first(3).each { |e| @stdout.puts "    #{e.path}" }
          @stdout.puts "    …(+#{g.entries.size - 3} more)" if g.entries.size > 3
        end
      else
        name = args.shift
        group = c.group(name)
        unless group
          @stderr.puts "#{@prog}: no such group: #{name}"
          return 1
        end
        @stdout.puts "[#{group.name}]"
        group.entries.each { |e| @stdout.puts "  #{e.to_line}" }
      end
      0
    end

    def cmd_edit
      editor = ENV['EDITOR'] || ENV['VISUAL'] || 'vi'
      FileUtils.mkdir_p(File.dirname(Config::DEFAULT_PATH))
      FileUtils.touch(Config::DEFAULT_PATH)
      Kernel.send(:exec, editor, Config::DEFAULT_PATH)
    end

    def presets_from_opts(opts)
      [opts[:permission], opts[:model], (opts[:yolo] ? 'yolo' : nil)].compact
    end

    # ---- launch path ------------------------------------------------------

    def run_launch
      cli_opts = Parser.new(@prog, @argv, config: config).parse
      return print_help if cli_opts[:help]

      if cli_opts[:continue] || cli_opts[:resume]
        @stderr.puts "#{@prog}: -c/-r do not compose with group mode; each project's conversation state is independent."
        raise UsageError.new('resume/continue in group mode', exit_status: 2)
      end

      defaults = @options_loader.load(dir: Dir.pwd, logger: @stderr)
      merged = merge_defaults(cli_opts, defaults)

      entries = resolve_entries(cli_opts, merged)
      if entries.empty?
        @stderr.puts "#{@prog}: no projects resolved — nothing to launch."
        raise UsageError.new('no projects', exit_status: 1)
      end

      label = resolve_label(cli_opts, entries, merged)
      dashboard = "#{DASHBOARD_PREFIX}#{label}"
      timestamp = Time.now.strftime('%y-%m-%d-%H%M')

      ensure_sources(entries, merged, timestamp)
      build_dashboard(dashboard, entries)
      focus(dashboard)
      0
    end

    def resolve_entries(cli_opts, merged)
      entries = Resolver.new(cli_opts, merged, config: config, prog: @prog).resolve
      return entries unless entries.empty?

      picked = InteractivePicker.new(config: config).call
      cli_opts[:named_groups].concat(picked[:named_groups])
      cli_opts[:ad_hoc_paths].concat(picked[:ad_hoc_paths])
      Resolver.new(cli_opts, merged, config: config, prog: @prog).resolve
    end

    def merge_defaults(cli, defaults)
      {
        permission: cli[:permission] || defaults[:permission],
        model: cli[:model] || defaults[:model],
        yolo: cli[:yolo] || defaults[:yolo],
        rc: cli[:rc] || defaults[:rc],
        label: cli[:label_override] || defaults.dig(:group, :label)
      }
    end

    def resolve_label(_cli_opts, entries, merged)
      return merged[:label] if merged[:label]
      return entries.first[:from_group] if entries.size == entries.count { |e| e[:from_group] } &&
                                           entries.map { |e| e[:from_group] }.uniq.size == 1 &&
                                           !entries.first[:from_group].is_a?(FalseClass) &&
                                           entries.first[:from_group].is_a?(String)

      Time.now.strftime('%y-%m-%d-%H%M')
    end

    def ensure_sources(entries, merged, timestamp)
      entries.each do |entry|
        session = entry[:session]
        next if @tmux.has_session?(session)

        flags = entry[:resolved_flags].dup
        if merged[:rc]
          flags += ['--remote-control',
                    '--remote-control-session-name-prefix', "#{session}-#{timestamp}"]
        end
        cmd = ['claude', *flags, *entry[:extra_args]]
        @tmux.new_session_detached(session, entry[:path], cmd)
      end
    end

    def build_dashboard(dashboard, entries)
      unless @tmux.has_session?(dashboard)
        @tmux.new_session_detached(dashboard, Dir.home, [ENV['SHELL'] || 'sh'])
        @tmux.set_option(dashboard, 'renumber-windows', 'on')
      end

      existing_names = @tmux.list_windows(dashboard).map { |idx_name| idx_name[1] }

      entries.each do |entry|
        project_name = entry[:session].sub(/\Acc-/, '')
        next if existing_names.include?(project_name)

        @tmux.link_window("#{entry[:session]}:0", dashboard)
        last_idx, = @tmux.list_windows(dashboard).last
        @tmux.rename_window("#{dashboard}:#{last_idx}", project_name)
      end

      project_names = entries.map { |e| e[:session].sub(/\Acc-/, '') }
      @tmux.list_windows(dashboard).each do |idx, name|
        @tmux.kill_window("#{dashboard}:#{idx}") unless project_names.include?(name)
      end
    end

    def focus(dashboard)
      if @tmux.inside_tmux?
        @tmux.switch_client(dashboard)
      else
        @tmux.attach(dashboard)
      end
    end
  end
end

require_relative 'group/parser'
require_relative 'group/management_parser'
require_relative 'group/resolver'
require_relative 'group/interactive_picker'
require_relative 'group/help'
