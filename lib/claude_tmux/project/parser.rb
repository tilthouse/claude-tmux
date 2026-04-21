# frozen_string_literal: true

require 'optparse'

module ClaudeTmux
  class Project
    # Parses `project` (aka `cct`) CLI args. All options are long-form;
    # positional is a single optional DIR. The `--` separator ends parsing
    # and passes the remainder verbatim to claude.
    class Parser
      def initialize(prog, argv)
        @prog = prog
        @argv = argv.dup
        @opts = {
          name: nil,
          permission: nil,
          model: nil,
          yolo: false,
          rc: false,
          continue: false,
          resume: false,
          resume_id: nil,
          dir: nil,
          extra_args: [],
          help: false
        }
      end

      def parse
        before, after = split_on_separator(@argv)
        @opts[:extra_args] = after

        parser = build_option_parser
        remaining = parser.parse(before)
        classify_positionals(remaining)

        raise UsageError, "#{@prog}: -c/--continue and -r/--resume are mutually exclusive" if @opts[:continue] && @opts[:resume]

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
          o.on('-n NAME', '--name NAME', String) { |v| @opts[:name] = v }
          o.on('-p MODE', '--permission MODE', Presets::VALID_PERMISSIONS) { |v| @opts[:permission] = v }
          o.on('-m MODEL', '--model MODEL', Presets::VALID_MODELS) { |v| @opts[:model] = v }
          o.on('--yolo') { @opts[:yolo] = true }
          o.on('--rc')   { @opts[:rc] = true }
          o.on('-c', '--continue') { @opts[:continue] = true }
          o.on('-r', '--resume [ID]') do |v|
            @opts[:resume] = true
            @opts[:resume_id] = v
          end
          o.on('-h', '--help') { @opts[:help] = true }
        end
      end

      def classify_positionals(positionals)
        case positionals.size
        when 0 then nil
        when 1 then @opts[:dir] = positionals[0]
        else
          raise UsageError,
                "#{@prog}: too many positional arguments (#{positionals.size}); 'project' accepts at most one DIR — " \
                'use `ccg` for multiple projects'
        end
      end
    end
  end
end
