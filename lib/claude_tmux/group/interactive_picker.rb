# frozen_string_literal: true

module ClaudeTmux
  class Group
    # `ccg` bare → multi-select fzf picker over group names + `sesh list`.
    # Returns { named_groups: [name, ...], ad_hoc_paths: [path, ...] } so the
    # caller can feed selections back through the normal Resolver pipeline.
    class InteractivePicker
      def initialize(config:)
        @config = config
      end

      def call
        lines = assemble_lines
        return empty_result if lines.empty?

        selected = fzf_select(lines)
        classify(selected)
      end

      private

      def empty_result
        { named_groups: [], ad_hoc_paths: [] }
      end

      def classify(selected)
        result = empty_result
        selected.each do |line|
          kind, label, = line.split("\t", 3)
          if kind == '[group]'
            result[:named_groups] << label if @config.group?(label)
          else
            result[:ad_hoc_paths] << label
          end
        end
        result
      end

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
    end
  end
end
