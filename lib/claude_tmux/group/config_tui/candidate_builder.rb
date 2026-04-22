# frozen_string_literal: true

module ClaudeTmux
  class Group
    class ConfigTui
      # Assembles the deduped add-entry candidate list:
      #   1. Entries in OTHER groups (excluding current_group)
      #   2. sesh-list entries
      #   3. ~/Developer walk (.git-bearing dirs, depth-first alpha)
      # Dedup by File.expand_path; first-seen wins.
      class CandidateBuilder
        DEFAULT_LIMIT = 200

        def initialize(config:, current_group:,
                       sesh: nil, dev_root: File.join(Dir.home, 'Developer'),
                       limit: DEFAULT_LIMIT)
          @config = config
          @current_group = current_group
          @sesh_lambda = sesh || -> { sesh_list_default }
          @dev_root = dev_root
          @limit = limit
        end

        def build
          rows = []
          seen = {}
          [group_rows, sesh_rows, dev_rows].each do |source|
            source.each do |row|
              key = File.expand_path(row[:path])
              next if seen.key?(key)

              seen[key] = true
              rows << row
              return rows if rows.size >= @limit
            end
          end
          rows
        end

        private

        def group_rows
          @config.groups.flat_map do |g|
            next [] if g.name == @current_group

            g.entries.map { |e| { tag: "[group:#{g.name}]", path: e.path } }
          end
        end

        def sesh_rows
          @sesh_lambda.call.map { |path| { tag: '[sesh]', path: path } }
        end

        def dev_rows
          return [] unless File.directory?(@dev_root)

          walk_alpha(@dev_root).map { |path| { tag: '[dev]', path: path } }
        end

        # Recursive depth-first walk; visits children in alpha order. A directory
        # containing `.git` is collected and not descended into; otherwise its
        # children are visited.
        def walk_alpha(root, result = [])
          Dir.children(root).sort.each do |name|
            path = File.join(root, name)
            next unless File.directory?(path)

            if File.exist?(File.join(path, '.git'))
              result << path
            else
              walk_alpha(path, result)
            end
          end
          result
        end

        def sesh_list_default
          out = IO.popen(['sesh', 'list', err: File::NULL], &:read) || ''
          out.each_line.map(&:chomp).reject(&:empty?)
        rescue Errno::ENOENT
          []
        end
      end
    end
  end
end
