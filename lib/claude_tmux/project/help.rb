# frozen_string_literal: true

module ClaudeTmux
  class Project
    module Help
      module_function

      def render(prog)
        <<~HELP
          #{prog} — launch or attach a per-project Claude Code tmux session.

          USAGE
            #{prog} [OPTIONS] [DIR] [-- claude args...]

          OPTIONS
            -p, --permission MODE   plan | accept | auto
            -m, --model MODEL       opus | sonnet
                --yolo              map to claude --dangerously-skip-permissions
                --rc                enable Remote Control (timestamped prefix)
            -n, --name NAME         override the session basename
            -c, --continue          continue most recent claude conversation in DIR
            -r, --resume [ID]       resume a specific conversation, or open picker
            -h, --help              show this help

            -c and -r are mutually exclusive, and both error out if the target
            tmux session is already running (they create claude with flags; they
            can't apply to an already-running process).

          POSITIONAL
            DIR   Project directory (default: current working directory).
                  `#{prog} ~/foo` starts claude in ~/foo with name derived from
                  that dir's .claude-tmux.toml or its git root.

          CONFIG CASCADE
            Defaults come from TOML files, merged with deeper files winning:
              ~/.config/cct/options.toml       (user-wide baseline)
              <any ancestor>/.claude-tmux.toml (walked $PWD → $HOME, inclusive)

              # .claude-tmux.toml
              permission = "plan"
              model      = "sonnet"
              rc         = false
              yolo       = false

              [project]
              name = "my-session"   # overrides derived basename

            CLI options always win over the cascade; the cascade wins over
            built-in defaults.

          SESSION NAMING
            Precedence (highest → lowest):
              1. -n / --name NAME
              2. [project] name from the options cascade
              3. <git-root>/basename of DIR (or cwd)
              4. basename of DIR (or cwd) if not a git repo

            Always prefixed with `cc-`. The tmux session name is the same
            regardless of modifiers — rerunning #{prog} in the same project
            attaches to the existing session. With --rc, a YY-MM-DD-HHMM
            timestamp is passed to claude as the RC prefix (so the mobile
            picker distinguishes invocations), but the tmux name is unchanged.

          EXAMPLES
            #{prog}                              # cwd project, no extras
            #{prog} -p plan -m sonnet            # plan mode + Sonnet
            #{prog} --yolo                       # skip all permission prompts
            #{prog} --rc                         # Remote Control enabled
            #{prog} -c                           # continue latest conversation
            #{prog} -r 7f3a-...                  # resume specific conversation
            #{prog} -n scratch                   # one-off: cc-scratch
            #{prog} ~/Developer/foo              # run in ~/Developer/foo
            #{prog} -- --add-dir ../sibling      # passthrough to claude
        HELP
      end
    end
  end
end
