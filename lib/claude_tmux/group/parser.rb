# frozen_string_literal: true

require 'optparse'

module ClaudeTmux
  class Group
    # Parses `group` (aka `ccg`) launch-mode args.
    #
    # Barewords are disambiguated:
    #   1. Pathlike (starts /, ./, ../, ~/, or is ~) → path
    #   2. Otherwise → config group name (must exist)
    #   3. Unknown → error with hint
    #
    # Presets are options only (`-p`, `-m`, `--yolo`); no bareword
    # preset classification remains in this parser.
    class Parser
      PATH_PREFIXES = %w[/ ./ ../ ~/].freeze

      def initialize(prog, argv, config:)
        @prog = prog
        @argv = argv.dup
        @config = config
        @opts = {
          label_override: nil,
          permission: nil,
          model: nil,
          yolo: false,
          rc: false,
          continue: false,
          resume: false,
          named_groups: [],
          ad_hoc_paths: [],
          extra_args: [],
          help: false
        }
      end

      def parse
        before, after = split_on_separator(@argv)
        @opts[:extra_args] = after

        parser = build_option_parser
        remaining = parser.parse(before)
        remaining.each { |token| classify_bareword(token) }

        @opts
      rescue OptionParser::ParseError => e
        raise UsageError, "#{@prog}: #{e.message}"
      end

      private

      def split_on_separator(argv)
        idx = argv.index('--')
        return [argv, []] if idx.nil?

        [argv[0...idx], argv[(idx + 1)..]]
      end

      def build_option_parser
        OptionParser.new do |o|
          o.on('-n LABEL', '--name LABEL', String) { |v| @opts[:label_override] = v }
          o.on('-p MODE', '--permission MODE', Presets::VALID_PERMISSIONS) { |v| @opts[:permission] = v }
          o.on('-m MODEL', '--model MODEL', Presets::VALID_MODELS) { |v| @opts[:model] = v }
          o.on('--yolo')  { @opts[:yolo] = true }
          o.on('--rc')    { @opts[:rc] = true }
          o.on('-c', '--continue') { @opts[:continue] = true }
          o.on('-r', '--resume')   { @opts[:resume] = true }
          o.on('-h', '--help')     { @opts[:help] = true }
        end
      end

      def classify_bareword(token)
        if pathlike?(token)
          @opts[:ad_hoc_paths] << token
        elsif @config&.group?(token)
          @opts[:named_groups] << token
        else
          raise UsageError,
                "#{@prog}: unknown argument '#{token}' — use ./#{token} for a path, " \
                "or add [#{token}] to ~/.config/cct/groups.conf"
        end
      end

      def pathlike?(token)
        PATH_PREFIXES.any? { |p| token.start_with?(p) } || token == '~'
      end
    end
  end
end
