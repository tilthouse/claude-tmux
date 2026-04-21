# frozen_string_literal: true

require 'toml-rb'

module ClaudeTmux
  # Cascading defaults loaded from TOML files.
  #
  # Precedence (highest wins, applied by callers on top of this result):
  #   1. CLI flags
  #   2. Per-entry config presets (group mode only, from groups.conf)
  #   3. .claude-tmux.toml cascade — files found walking $PWD → $HOME (inclusive)
  #      are merged, deeper dirs overriding shallower
  #   4. ~/.config/cct/options.toml  (user-wide baseline)
  #   5. Built-in defaults
  #
  # Schema:
  #   permission = "plan|accept|auto"
  #   model      = "opus|sonnet"
  #   yolo       = bool
  #   rc         = bool
  #
  #   [project]
  #   name  = "..."
  #
  #   [group]
  #   label = "..."
  class Options
    DOTFILE_NAME     = '.claude-tmux.toml'
    USER_CONFIG_PATH = File.expand_path('~/.config/cct/options.toml')

    VALID_PERMISSIONS = %w[plan accept auto].freeze
    VALID_MODELS      = %w[opus sonnet].freeze

    BLANK = {
      permission: nil,
      model: nil,
      yolo: false,
      rc: false,
      project: { name: nil },
      group: { label: nil }
    }.freeze

    def self.load(dir: Dir.pwd, home: Dir.home, user_config: USER_CONFIG_PATH, logger: $stderr)
      new(dir: dir, home: home, user_config: user_config, logger: logger).load
    end

    def initialize(dir:, home:, user_config:, logger:)
      @dir = File.expand_path(dir)
      @home = File.expand_path(home)
      @user_config = user_config
      @logger = logger
    end

    def load
      paths = discover
      paths.each_with_object(deep_dup(BLANK)) do |path, acc|
        data = parse(path)
        merge_into(acc, data, path: path)
      end
    end

    # Files returned in precedence order: shallowest first, deepest last,
    # so later entries override earlier ones. User-wide comes first (lowest
    # priority), then the cascade from $HOME-ward down to $PWD.
    def discover
      paths = []
      paths << @user_config if File.file?(@user_config)
      paths.concat(cascade_files.reverse)
      paths
    end

    private

    # Walk from $PWD upward; include every directory's dotfile that exists;
    # stop after $HOME is visited, or after '/' if $HOME is not an ancestor.
    # Returns deepest-first (so caller should reverse for shallow-first).
    def cascade_files
      found = []
      cursor = @dir
      loop do
        candidate = File.join(cursor, DOTFILE_NAME)
        found << candidate if File.file?(candidate)
        break if cursor == @home

        parent = File.dirname(cursor)
        break if parent == cursor

        cursor = parent
      end
      found
    end

    def parse(path)
      TomlRB.load_file(path)
    rescue TomlRB::ParseError => e
      raise ConfigError, "#{path}: #{e.message}"
    end

    def merge_into(acc, data, path:)
      data.each do |key, value|
        case key
        when 'permission' then acc[:permission] = enum!(key, value, VALID_PERMISSIONS, path)
        when 'model'      then acc[:model]      = enum!(key, value, VALID_MODELS, path)
        when 'yolo'       then acc[:yolo]       = bool!(key, value, path)
        when 'rc'         then acc[:rc]         = bool!(key, value, path)
        when 'project'    then merge_project(acc, value, path: path)
        when 'group'      then merge_group(acc, value, path: path)
        else warn_unknown(key, path)
        end
      end
    end

    def merge_project(acc, data, path:)
      raise ConfigError, "#{path}: [project] must be a table" unless data.is_a?(Hash)

      data.each do |key, value|
        case key
        when 'name' then acc[:project][:name] = string!(key, value, path)
        else warn_unknown("project.#{key}", path)
        end
      end
    end

    def merge_group(acc, data, path:)
      raise ConfigError, "#{path}: [group] must be a table" unless data.is_a?(Hash)

      data.each do |key, value|
        case key
        when 'label' then acc[:group][:label] = string!(key, value, path)
        else warn_unknown("group.#{key}", path)
        end
      end
    end

    def enum!(key, value, valid, path)
      raise ConfigError, "#{path}: '#{key}' must be a string" unless value.is_a?(String)
      raise ConfigError, "#{path}: '#{key}' must be one of #{valid.join('/')}, got '#{value}'" unless valid.include?(value)

      value
    end

    def bool!(key, value, path)
      return value if [true, false].include?(value)

      raise ConfigError, "#{path}: '#{key}' must be a boolean, got #{value.inspect}"
    end

    def string!(key, value, path)
      raise ConfigError, "#{path}: '#{key}' must be a string" unless value.is_a?(String)

      value
    end

    def warn_unknown(key, path)
      @logger.puts "claude-tmux: #{path}: unknown option '#{key}' (ignored)"
    end

    def deep_dup(hash)
      hash.each_with_object({}) do |(k, v), out|
        out[k] = v.is_a?(Hash) ? deep_dup(v) : v
      end
    end
  end
end
