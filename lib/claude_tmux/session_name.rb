# frozen_string_literal: true

module ClaudeTmux
  # Computes a `cc-<basename>` session name from a directory. The name
  # argument (from CLI `-n`, or from an options-cascade `[project] name`)
  # takes precedence over derivation. Pure; no tmux interaction.
  module SessionName
    SESSION_PREFIX = 'cc-'

    module_function

    def compute(dir: Dir.pwd, name: nil)
      return with_prefix(name) if name && !name.to_s.empty?

      root = git_root(dir) || File.expand_path(dir)
      with_prefix(File.basename(root))
    end

    def git_root(dir)
      out = IO.popen(['git', '-C', dir, 'rev-parse', '--show-toplevel', err: File::NULL], &:read)
      return nil if out.nil? || out.strip.empty?

      out.strip
    rescue Errno::ENOENT
      nil
    end

    def with_prefix(name)
      "#{SESSION_PREFIX}#{name}"
    end
  end
end
