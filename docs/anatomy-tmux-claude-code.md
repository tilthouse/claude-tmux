# Anatomy of a tmux + Claude Code session

Reference for the terms and pieces of UI you see when running Claude Code
inside tmux. The "tab bar" is the **window list** inside the **status
line**; the slug we add to dashboard tabs is **spliced** into the
**`window-status-format`** tmux uses to render each window's entry.

Box diagrams below use ASCII so they line up in any monospace font; the
actual glyphs Claude Code and tmux render appear in the tables and the
"How the splice works" section.

## tmux

```
                   +-- [1] terminal-emulator chrome (iTerm2 title bar, etc.)
                   |       (set by `set-titles` + `set-titles-string`)
                   v
   +------------------------------------------------------------+
   | Some Title  - iTerm2                                       |  <- terminal title (OSC 0/2)
   +------------------------------------------------------------+
   |                                                            |
   |   [2] PANE     --- runs one program                        |
   |                pane_title (#T) <- OSC 2 from program       |
   |                pane_current_command (#{...})               |
   |                pane_id (#D)                                |
   |  ----- [3] pane border -----                               |
   |   [2] another PANE                                         |
   |                                                            |
   +--+----------------------------------------------------+----+
   |L |  1 site: * Claude Code   2 arni: * Claude Code     |  R |  <- [4] STATUS LINE
   +--+----------------------------------------------------+----+
      ^ status-left            ^ window list           ^ status-right
       (#{status-left})           (one segment per      (#{status-right})
                                  window in the
                                  current session)
```

| Marker | Term | What it is | Format ref | Example |
|---|---|---|---|---|
| – | **Server** | the tmux daemon | – | one per user |
| – | **Client** | a terminal attached to the server | `#{client_tty}` | `/dev/ttys004` |
| – | **Session** | a named collection of windows | `#{session_name}` (`#S`) | `cc-claude-tmux` |
| [2] | **Window** | fills the client viewport (a "tab") | `#{window_name}` (`#W`), `#{window_index}` (`#I`), `#{window_flags}` (`#F`) | `#W = 2.1.117` (Claude set it via OSC 2) |
| [2] | **Pane** | a rectangular subregion inside a window | `#{pane_title}` (`#T`), `#{pane_current_command}` | `#T = ⠂ Fix ccg command nil conversion error` |
| [3] | **Pane border** | divider between panes; can carry its own status line | `pane-border-format`, `pane-border-status` | – |
| [4] | **Status line** | the bottom (or top) info bar | `status` on/off, `status-style`, `status-position` | bottom, catppuccin theme |
| [4]L | **status-left** | left segment of status line | `status-left` | catppuccin's `#S` block |
| [4]R | **status-right** | right segment of status line | `status-right` | catppuccin's date/time/host |
| [4] | **Window list** | the middle of the status line; one entry per window | – | the "tab bar" |
| – | **Window status** | one entry inside the window list | `window-status-format` (inactive), `window-status-current-format` (active) | what the dashboard splice modifies |
| – | **Message line** | transient overlay for `display-message`, errors, etc. | `message-style` | – |
| – | **Mode** | overlay state like copy-mode, choose-tree, the prefix table | – | `prefix + s` enters choose-tree |
| – | **Format** | tmux's `#{…}` template language | – | `#{?@ccg-project,#{@ccg-project}: ,}#T` |
| – | **Option** | a variable; scoped server / session / window / pane | `set-option [-s\|-w] -t <target>` | `base-index 1` is yours (window option) |
| – | **User option** | custom option with `@` prefix | `#{@my-thing}` | `@ccg-project = site` |

In the diagram above, the `*` placeholder in the window-list strip
represents Claude Code's actual spinner glyph (`✳`); it's drawn as `*`
inside the box only so the right border lines up.

### Inspecting in real time

```bash
tmux display-message -p '#{session_name} #{window_index}:#{window_name} pane=#{pane_title}'
tmux show-options -gv window-status-format        # global value
tmux show-options -wv -t <window> @ccg-project    # per-window value
tmux list-windows -t <session> -F '#{window_index} #{window_name} #{pane_title}'
```

## Claude Code

```
   +------------------------------------------------------------------+
   |  * Welcome to Claude Code v2.1.117                               |  <- [a] welcome banner (one-shot, on launch)
   |                                                                  |
   |  ----------- conversation transcript -----------                 |  <- [b] transcript / message log
   |                                                                  |
   |  > User message text...                                          |  <- [c] user message
   |                                                                  |
   |  o Assistant response prose...                                   |  <- [d] assistant message
   |                                                                  |
   |  o Bash(ls -la)                                                  |  <- [e] tool use block (call)
   |    L total 24                                                    |  <- [f] tool result block
   |      drwxr-xr-x  ...                                             |
   |                                                                  |
   |  o More assistant prose...                                       |
   |                                                                  |
   |  +-------------------------------------------------------------+ |
   |  | Do you want to allow this?                                  | |  <- [g] permission prompt
   |  | > 1. Yes                                                    | |     (numbered options, > marks current)
   |  |   2. Yes, and don't ask again for this command              | |
   |  |   3. No, and tell Claude what to do differently             | |
   |  +-------------------------------------------------------------+ |
   |                                                                  |
   |  * Streaming...  (esc to interrupt)                              |  <- [h] in-flight indicator
   |                                                                  |
   +------------------------------------------------------------------+
   | > what you type goes here                                        |  <- [i] input prompt
   |                                                                  |
   |   L  context: 41% used . opus-4-7[1m] . auto-accept . /clear     |  <- [j] status line / chrome
   +------------------------------------------------------------------+
            ^ [k] pane_title (sent to tmux): "<task summary>"
```

ASCII-substitution key (what Claude Code actually renders):

| In diagram | Real glyph | Where |
|---|---|---|
| `*` (welcome line) | `✻` | banner |
| `o` (assistant lines) | `⏺` | each assistant message + tool calls |
| `L` (tool result indent) | `⎿` | tool result and Claude's status indent |
| `>` (permission prompt cursor) | `❯` | currently-selected option |
| `*` (in-flight) | `✳` | spinner |
| `.` (status separators) | `·` | middle dot between status fields |

| ID | Term | What it is |
|----|------|------------|
| [a] | **Welcome banner / startup screen** | Shown on `claude` launch. Version, model, working dir. Disappears once you scroll. |
| [b] | **Transcript** (also: conversation, message log) | Append-only log of the conversation. Scrollback works. |
| [c] | **User message** / **user turn** | What you sent. |
| [d] | **Assistant message** / **assistant turn** | What Claude sent back. Prose between tool calls. |
| [e] | **Tool use** / **tool call block** | Claude invoking a tool — `Bash`, `Read`, `Edit`, etc. Tool name + arguments. |
| [f] | **Tool result** | Output the tool returned. Often collapsed/truncated by default. |
| [g] | **Permission prompt** | The numbered "Do you want to…" overlay when not in auto/yolo mode. `❯` marks the cursor. The strings `Do you want` and `❯ 1.` are what `ccs`'s glyph logic greps for. |
| [h] | **In-flight indicator** / **spinner** | The `✳` glyph + `(esc to interrupt)` while a tool call or stream is running. `ccs` greps for `esc to interrupt` for its "active" glyph. |
| [i] | **Input prompt** / **composer** | Where you type. Supports multi-line, `/slash` commands, `!shell`, file pasting. |
| [j] | **Claude Code status line** | Bottom-of-screen chrome inside the pane: model, context %, mode (plan / accept / auto / yolo), shortcuts. **Different from tmux's status line.** |
| [k] | **Pane title Claude sets** | Sent via OSC 2; reflects the current task. Why our `ccg` dashboard splices `#T` so it carries through. |

### Cross-cutting concepts

| Term | Meaning |
|---|---|
| **Session** | One conversation. Has a UUID, can be resumed (`claude -r`) or continued (`claude -c`). |
| **Permission mode** | `default` / `plan` / `acceptEdits` / `bypassPermissions` (yolo). Controls when [g] appears. |
| **Slash command** | `/help`, `/clear`, `/loop`, `/ultrareview`, etc. — handled inline. |
| **Skill** | A bundled instruction set the agent loads (e.g. `using-superpowers`). |
| **Subagent** | A Claude instance spawned via the `Task` (or `Agent`) tool with its own isolated context. |
| **MCP server** | External tool provider plugged in via the Model Context Protocol. Tools show up prefixed `mcp__<server>__<tool>`. |
| **Hooks** | Shell commands the harness runs on events (SessionStart, PreToolUse, etc.). Configured in `settings.json`. |
| **Output style** | A persona/format mode (e.g. "concise", "explanatory") set per-session. |

## Confusion-clarifier on the two "status lines"

- **tmux status line** = the bar at [4]. Shows windows/sessions.
- **Claude Code status line** = the bar at [j]. Shows model/context/mode. Lives *inside* the pane, drawn by Claude.

## How the `ccg` dashboard splice works (concrete example)

Your global format (catppuccin):

```
#[fg=#11111b,bg=#{@thm_overlay_2}]#[fg=#181825,reverse]#[none]#I #[fg=#cdd6f4,bg=#{@thm_surface_0}] #T#[fg=#181825,reverse]#[none]
```

After ccg splices `#{?@ccg-project,#{@ccg-project}: ,}` immediately before `#T`:

```
#[fg=#11111b,bg=#{@thm_overlay_2}]#[fg=#181825,reverse]#[none]#I #[fg=#cdd6f4,bg=#{@thm_surface_0}] #{?@ccg-project,#{@ccg-project}: ,}#T#[fg=#181825,reverse]#[none]
```

Each linked window in the dashboard also gets `@ccg-project = <slug>` set
on it (a per-window user option). The conditional renders `<slug>: ` only
when that option is present, so the source `cc-<name>` sessions (where
the option isn't set) keep their normal tab appearance.
