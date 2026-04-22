# frozen_string_literal: true

require 'fileutils'

module ClaudeTmux
  # Parser and writer for ~/.config/cct/groups.conf.
  #
  # Format:
  #   [group-name]
  #   ~/Developer/projA
  #   ~/Developer/projB plan
  #   ~/Developer/projC plan sonnet
  #
  #   # comments allowed anywhere
  #   [evening]
  #   ~/Developer/projD
  #
  # Rules:
  #   - '#' starts a comment to end of line.
  #   - Blank lines ignored.
  #   - '[name]' starts a group; names match /\A[A-Za-z0-9_-]+\z/.
  #   - Paths must be absolute ('/...') or tilde-prefixed ('~/...').
  #   - After the path, any number of preset tokens (plan|accept|auto|
  #     yolo|opus|sonnet) may appear.
  #   - Reserved group names (`add`, `rm`, `list`, `edit`) are rejected
  #     at write time; a config hand-edited to include them is parsed
  #     but will fail at subcommand dispatch if invoked.
  class Config
    DEFAULT_PATH = File.expand_path('~/.config/cct/groups.conf')

    GROUP_NAME_RE = /\A[A-Za-z0-9_-]+\z/
    RESERVED_WORDS = %w[add rm list edit group help config].freeze

    Group = Struct.new(:name, :entries, keyword_init: true)
    Entry = Struct.new(:path, :presets, keyword_init: true) do
      def normalized_path
        File.expand_path(path)
      end

      def to_line
        ([path] + presets).join(' ')
      end
    end

    attr_reader :path

    def initialize(path: DEFAULT_PATH)
      @path = path
      @groups = {}
      @order = []
    end

    def self.load(path: DEFAULT_PATH)
      new(path: path).tap(&:load)
    end

    def load
      return self unless File.file?(@path)

      current = nil
      File.foreach(@path).with_index(1) do |raw, lineno|
        line = strip_comment(raw).strip
        next if line.empty?

        if (m = line.match(/\A\[(.+)\]\z/))
          current = open_group(m[1], lineno)
        else
          raise ConfigError, "#{@path}:#{lineno}: entry outside of any [group] section" if current.nil?

          add_entry_from_line(current, line, lineno)
        end
      end
      self
    end

    def groups
      @order.map { |n| @groups[n] }
    end

    def group(name)
      @groups[name]
    end

    def group?(name)
      @groups.key?(name)
    end

    def group_names
      @order.dup
    end

    def add_entry(group_name, path, presets = [])
      validate_group_name!(group_name)
      validate_path!(path)
      validate_presets!(presets)

      unless @groups.key?(group_name)
        @groups[group_name] = Group.new(name: group_name, entries: [])
        @order << group_name
      end

      group = @groups[group_name]
      existing = group.entries.find { |e| File.expand_path(e.path) == File.expand_path(path) }
      if existing
        existing.presets = presets
      else
        group.entries << Entry.new(path: canonicalize_path(path), presets: presets)
      end
      self
    end

    def remove_entry(group_name, path)
      group = @groups[group_name]
      return false unless group

      before = group.entries.size
      expanded = File.expand_path(path)
      group.entries.reject! { |e| File.expand_path(e.path) == expanded }
      group.entries.size != before
    end

    def delete_group(group_name)
      return false unless @groups.key?(group_name)

      @groups.delete(group_name)
      @order.delete(group_name)
      true
    end

    def replace_entry_presets(group_name, path, new_presets)
      group = @groups[group_name]
      raise ConfigError, "no such group: #{group_name}" unless group

      validate_presets!(new_presets)

      expanded = File.expand_path(path)
      entry = group.entries.find { |e| File.expand_path(e.path) == expanded }
      raise ConfigError, "no such entry in [#{group_name}]: #{path}" unless entry

      entry.presets = new_presets
      true
    end

    def move_entry(group_name, from_idx, to_idx)
      group = @groups[group_name]
      raise ConfigError, "no such group: #{group_name}" unless group
      return true if from_idx == to_idx

      size = group.entries.size
      unless (0...size).cover?(from_idx) && (0...size).cover?(to_idx)
        raise ConfigError, "index out of range (size=#{size}): #{from_idx}, #{to_idx}"
      end

      entry = group.entries.delete_at(from_idx)
      group.entries.insert(to_idx, entry)
      true
    end

    def rename_group(old_name, new_name)
      raise ConfigError, "no such group: #{old_name}" unless @groups.key?(old_name)
      raise ConfigError, "group already exists: #{new_name}" if @groups.key?(new_name)

      validate_group_name!(new_name)

      group = @groups.delete(old_name)
      group.name = new_name
      @groups[new_name] = group
      @order[@order.index(old_name)] = new_name
      true
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, 'w') do |f|
        @order.each_with_index do |name, i|
          f.puts if i.positive?
          f.puts "[#{name}]"
          @groups[name].entries.each { |e| f.puts e.to_line }
        end
      end
      self
    end

    # Normalize a path for storage: if absolute under $HOME, rewrite to ~/...;
    # if already tilde-prefixed, keep as-is; leave other absolute paths alone.
    def canonicalize_path(path)
      return path if path.start_with?('~/') || path == '~'

      expanded = File.expand_path(path)
      home = Dir.home
      return expanded.sub(home, '~') if expanded == home || expanded.start_with?("#{home}/")

      expanded
    end

    def absolute_or_tilde?(path)
      path.start_with?('/') || path.start_with?('~/') || path == '~'
    end

    def dirty?
      disk = self.class.new(path: @path).load
      to_signature != disk.send(:to_signature)
    end

    PERMISSION_PRESETS = (Presets::VALID_PERMISSIONS + ['yolo']).freeze
    MODEL_PRESETS      = Presets::VALID_MODELS
    ALL_PRESETS        = (PERMISSION_PRESETS + MODEL_PRESETS).freeze

    protected

    # Stable structural signature: order-preserved [name, [path, presets]] tuples.
    # Used by #dirty? to compare in-memory state to a freshly-loaded disk snapshot.
    def to_signature
      @order.map do |name|
        entries = @groups[name].entries.map { |e| [e.path, e.presets.dup] }
        [name, entries]
      end
    end

    private

    def strip_comment(line)
      line.sub(/(?<!\\)#.*/, '')
    end

    def open_group(name, lineno)
      raise ConfigError, "#{@path}:#{lineno}: invalid group name: #{name.inspect}" unless name.match?(GROUP_NAME_RE)

      unless @groups.key?(name)
        @groups[name] = Group.new(name: name, entries: [])
        @order << name
      end
      @groups[name]
    end

    def add_entry_from_line(group, line, lineno)
      tokens = line.split(/\s+/)
      path = tokens.shift
      raise ConfigError, "#{@path}:#{lineno}: relative paths not allowed: #{path}" unless absolute_or_tilde?(path)

      invalid = tokens - ALL_PRESETS
      raise ConfigError, "#{@path}:#{lineno}: unknown preset(s) after path: #{invalid.join(' ')}" unless invalid.empty?

      group.entries << Entry.new(path: path, presets: tokens)
    end

    def validate_group_name!(name)
      raise ConfigError, "invalid group name: #{name.inspect}" unless name.match?(GROUP_NAME_RE)
      return unless RESERVED_WORDS.include?(name)

      raise ConfigError, "group name '#{name}' is reserved (matches a subcommand)"
    end

    def validate_path!(path)
      return if absolute_or_tilde?(path)

      raise ConfigError, "paths must be absolute or ~-prefixed: #{path}"
    end

    def validate_presets!(presets)
      invalid = presets - ALL_PRESETS
      raise ConfigError, "unknown preset(s): #{invalid.join(' ')}" unless invalid.empty?

      perms = presets & PERMISSION_PRESETS
      raise ConfigError, "conflicting permission presets: #{perms.join(' ')}" if perms.size > 1

      models = presets & MODEL_PRESETS
      raise ConfigError, "conflicting model presets: #{models.join(' ')}" if models.size > 1
    end
  end
end
