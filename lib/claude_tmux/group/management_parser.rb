# frozen_string_literal: true

require 'optparse'

module ClaudeTmux
  class Group
    # Parses args for `ccg add`/`rm`/`list`/`edit` management subcommands.
    # Only `add` accepts option flags (per-entry preset storage); `rm`/
    # `list`/`edit` just take positionals or nothing, but we share the
    # parser so any `-p`/`-m`/`--yolo` flag works identically across them.
    class ManagementParser
      def initialize(prog, argv)
        @prog = prog
        @argv = argv.dup
        @opts = {
          permission: nil,
          model: nil,
          yolo: false
        }
      end

      def parse
        parser = OptionParser.new do |o|
          o.on('-p MODE', '--permission MODE', Presets::VALID_PERMISSIONS) { |v| @opts[:permission] = v }
          o.on('-m MODEL', '--model MODEL', Presets::VALID_MODELS) { |v| @opts[:model] = v }
          o.on('--yolo') { @opts[:yolo] = true }
        end
        positional = parser.parse(@argv)
        [@opts, positional]
      rescue OptionParser::ParseError => e
        raise UsageError, "#{@prog}: #{e.message}"
      end
    end
  end
end
