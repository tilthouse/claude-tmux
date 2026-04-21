# frozen_string_literal: true

module ClaudeTmux
  class Group
    # Flattens parsed options + merged defaults into a deduplicated list of
    # entries:
    #   { session:, path:, resolved_flags:, extra_args:, from_group: }
    #
    # Flag resolution precedence (highest wins):
    #   per-entry config presets > merged CLI/dotfile defaults > none.
    class Resolver
      def initialize(cli_opts, merged_defaults, config:, prog:)
        @cli_opts = cli_opts
        @merged = merged_defaults
        @config = config
        @prog = prog
      end

      def resolve
        by_session = {}

        @cli_opts[:named_groups].each do |name|
          group = @config.group(name)
          unless group
            warn "#{@prog}: group [#{name}] not found in config — skipping"
            next
          end
          group.entries.each { |e| absorb_entry(by_session, e.path, e.presets, from_group: name) }
        end

        @cli_opts[:ad_hoc_paths].each do |path|
          absorb_entry(by_session, path, [], from_group: false)
        end

        by_session.values
      end

      private

      def absorb_entry(acc, path, per_entry_presets, from_group:)
        expanded = File.expand_path(path)
        unless File.directory?(expanded)
          warn "#{@prog}: path does not exist (skipped): #{path}"
          return
        end

        session = SessionName.compute(dir: expanded)
        flags = if per_entry_presets.empty?
                  default_flags
                else
                  flags_from_legacy_presets(per_entry_presets)
                end

        acc[session] = {
          session: session,
          path: expanded,
          resolved_flags: flags,
          extra_args: @cli_opts[:extra_args],
          from_group: from_group
        }
      end

      def default_flags
        Presets.all_flags(
          permission: @merged[:permission],
          model: @merged[:model],
          yolo: @merged[:yolo]
        )
      end

      # groups.conf still stores per-entry presets as bareword tokens (for
      # backwards compat). Translate them into claude flags.
      def flags_from_legacy_presets(words)
        permission = (words & Presets::VALID_PERMISSIONS).first
        model      = (words & Presets::VALID_MODELS).first
        yolo       = words.include?('yolo')
        Presets.all_flags(permission: permission, model: model, yolo: yolo)
      end
    end
  end
end
