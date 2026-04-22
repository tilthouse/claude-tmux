# frozen_string_literal: true

module ClaudeTmux
  class Group
    module Help
      module_function

      def render(prog)
        <<~HELP
          #{prog} — launch Claude in multiple projects at once, one tmux window per project.

          USAGE
            #{prog} [OPTIONS] [GROUP|PATH]...       # launch (bare → picker)
            #{prog} add  <group> <path> [OPTIONS]   # add/update entry
            #{prog} rm   <group> [<path>]           # remove entry or group
            #{prog} list [<group>]                  # list all groups / dump one
            #{prog} edit                            # open groups.conf in $EDITOR
            #{prog} config                          # interactive TUI for managing groups

            Subcommands resolve by unique prefix (e.g. `#{prog} c` → `config`).

          OPTIONS (launch + add)
            -p, --permission MODE   plan | accept | auto
            -m, --model MODEL       opus | sonnet
                --yolo              --dangerously-skip-permissions
                --rc                Remote Control on newly-created sources
            -n, --name LABEL        override grouping-session label
            -h, --help              show this help

            -c and -r are rejected in group mode (each project's conversation
            is independent).

          POSITIONAL (launch)
            Barewords are disambiguated in order:
              1. Pathlike (starts /, ./, ../, ~/, or is ~) → ad-hoc path
              2. Otherwise → named group from config (must exist)
              3. Unknown → error with hint

            No presets here — use -p/-m/--yolo.

          CONFIG
            ~/.config/cct/groups.conf  — INI-style, per-group entry lists.
              [morning]
              ~/Developer/projA
              ~/Developer/projB plan
              ~/Developer/projC plan sonnet

              [evening]
              ~/Developer/projD

            ~/.config/cct/options.toml and any .claude-tmux.toml walking
            $PWD → $HOME (inclusive) provide group-mode defaults (e.g.
            [group] label = "work"), with CLI flags winning. Per-entry
            preset tokens in groups.conf override defaults for THAT source.

          SESSION NAMING
            Grouping:   ccg-<name>   for named groups
                        ccg-<label>  with -n <label>
                        ccg-<YY-MM-DD-HHMM>   ad-hoc, no label

            Per-project sources:   cc-<basename>   (same as `cct` produces)

          BEHAVIOR
            - Each project's source session is created via cct-style launch
              if missing, or attached (flags ignored on attach, same as cct).
              Dashboard is a pure view — killing it doesn't kill sources.
            - --rc passes a single shared YY-MM-DD-HHMM timestamp to every
              newly-created source's --remote-control-session-name-prefix.
        HELP
      end
    end
  end
end
