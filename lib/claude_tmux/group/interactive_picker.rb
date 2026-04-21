# frozen_string_literal: true

module ClaudeTmux
  class Group
    # `ccg` bare → multi-select fzf picker over group names + `sesh list`.
    # Returns a list of {path:, presets:, from_group:} entries, already
    # expanded (groups flattened into their constituent paths).
    class InteractivePicker
      def initialize(config:)
        @config = config
      end

      def call
        lines = assemble_lines
        return [] if lines.empty?

        selected = fzf_select(lines)
        selected.flat_map { |line| expand(line) }
      end

      private

      def assemble_lines
        group_lines = @config.group_names.map do |n|
          count = @config.group(n).entries.size
          "[group]\t#{n}\t(#{count} project#{'s' if count != 1})"
        end
        sesh_lines = sesh_list.map { |name| "\t#{name}\t" }
        group_lines + sesh_lines
      end

      def sesh_list
        out = IO.popen(['sesh', 'list', err: File::NULL], &:read) || ''
        out.each_line.map(&:chomp).reject(&:empty?)
      rescue Errno::ENOENT
        []
      end

      def fzf_select(lines)
        input = lines.join("\n")
        out = IO.popen(['fzf', '--multi', '--delimiter=\t', '--with-nth=1,2,3',
                        '--prompt=ccg> ', '--height=60%', '--reverse'],
                       'r+') do |io|
          io.write(input)
          io.close_write
          io.read
        end
        return [] unless out

        out.each_line.map(&:chomp).reject(&:empty?)
      rescue Errno::ENOENT
        warn 'ccg: fzf not found on PATH — interactive picker requires fzf + sesh.'
        []
      end

      def expand(line)
        kind, label, = line.split("\t", 3)
        if kind == '[group]'
          group = @config.group(label)
          return [] unless group

          group.entries.map do |e|
            { path: File.expand_path(e.path), presets: e.presets, from_group: true }
          end
        else
          [{ path: File.expand_path(label), presets: [], from_group: false }]
        end
      end
    end
  end
end
