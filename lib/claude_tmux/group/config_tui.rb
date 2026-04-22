# frozen_string_literal: true

module ClaudeTmux
  class Group
    # Interactive TUI for ~/.config/cct/groups.conf. State-stack loop:
    # each screen returns one of [:next, name, payload], [:back], or [:exit].
    # Mutations go through the in-memory @config; on exit, prompt save/discard.
    class ConfigTui
      def initialize(config_path: Config::DEFAULT_PATH, prompt: Prompt.new, stderr: $stderr)
        @config_path = config_path
        @config = Config.load(path: config_path)
        @prompt = prompt
        @stderr = stderr
      end

      def run
        stack = [[:groups_list, nil]]
        until stack.empty?
          screen, payload = stack.last
          result = dispatch_screen(screen, payload)
          case result.first
          when :next then stack.push([result[1], result[2]])
          when :back then stack.pop
          when :exit then stack.clear
          end
        end
        save_prompt
        0
      end

      private

      def dispatch_screen(screen, payload)
        send(:"screen_#{screen}", payload)
      rescue ConfigError => e
        @stderr.puts "ccg: #{e.message}"
        [:next, screen, payload]
      end

      def screen_groups_list(_payload)
        items = ['[+ new group]'] + @config.group_names.map do |n|
          count = @config.group(n).entries.size
          "[#{n}] (#{count} project#{'s' if count != 1})"
        end
        result = @prompt.choose(items, header: header_with_dirty)
        return [:exit] if result[:item].nil?

        if result[:item] == '[+ new group]'
          [:back] # implemented in Task 12
        else
          name = result[:item][/\[(.+?)\]/, 1]
          [:next, :group_view, { group: name }]
        end
      end

      def header_with_dirty
        marker = @config.dirty? ? ' *' : ''
        "ccg config — groups#{marker}"
      end

      def save_prompt
        return unless @config.dirty?

        @config.save if @prompt.confirm(label: "Save changes to #{@config_path}?")
      end
    end
  end
end
