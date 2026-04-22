# Anatomy of a tmux + Claude Code session

Reference for the terms and pieces of UI you see when running Claude Code
inside tmux. The "tab bar" is the **window list** inside the **status
line**; the slug we add to dashboard tabs is **spliced** into the
**`window-status-format`** tmux uses to render each window's entry.

## tmux

```
                    ┌─ ① terminal-emulator chrome (iTerm2 title bar, etc.)
                    │   ── set by `set-titles` + `set-titles-string`
                    ▼
   ┌────────────────────────────────────────────────────────────┐
   │ Some Title  – iTerm2                                       │  ← terminal title (OSC 0/2)
   ├────────────────────────────────────────────────────────────┤
   │                                                            │
   │                                                            │
   │   ② PANE        ──── runs one program                      │
   │                      pane_title (#T) ← OSC 2 from program  │
   │                      pane_current_command (#{...})         │
   │                      pane_id (#D)                          │
   │  ┄┄┄┄┄ ③ pane border ┄┄┄┄┄                                 │
   │   ② another PANE                                            │
   │                                                            │
   ├──┬──────────────────────────────────────────────────┬──────┤
   │L │  1 site: ✳ Claude Code   2 arni: ✳ Claude Code   │   R  │  ← ④ STATUS LINE
   └──┴──────────────────────────────────────────────────┴──────┘
      ▲ status-left            ▲ window list           ▲ status-right
       (#{status-left})           (one segment per      (#{status-right})
                                  window in the
                                  current session)
```

| # | Term | What it is | Format ref | Example |
|---|---|---|---|---|
| – | **Server** | the tmux daemon | – | one per user |
| – | **Client** | a terminal attached to the server | `#{client_tty}` | `/dev/ttys004` |
| – | **Session** | a named collection of windows | `#{session_name}` (`#S`) | `cc-claude-tmux` |
| ② | **Window** | fills the client viewport (a "tab") | `#{window_name}` (`#W`), `#{window_index}` (`#I`), `#{window_flags}` (`#F`) | `#W = 2.1.117` (Claude set it via OSC 2) |
| ② | **Pane** | a rectangular subregion inside a window | `#{pane_title}` (`#T`), `#{pane_current_command}` | `#T = ⠂ Fix ccg command nil conversion error` |
| ③ | **Pane border** | divider between panes; can carry its own status line | `pane-border-format`, `pane-border-status` | – |
| ④ | **Status line** | the bottom (or top) info bar | `status` on/off, `status-style`, `status-position` | bottom, catppuccin theme |
| ④L | **status-left** | left segment of status line | `status-left` | catppuccin's `#S` block |
| ④R | **status-right** | right segment of status line | `status-right` | catppuccin's date/time/host blocks |
| ④ | **Window list** | the middle of the status line; one entry per window | – | the "tab bar" |
| – | **Window status** | one entry inside the window list | `window-status-format` (inactive), `window-status-current-format` (active) | what the dashboard splice modifies |
| – | **Message line** | transient overlay for `display-message`, errors, etc. | `message-style` | – |
| – | **Mode** | overlay state like copy-mode, choose-tree, the prefix table | – | `prefix + s` enters choose-tree |
| – | **Format** | tmux's `#{…}` template language | – | `#{?@ccg-project,#{@ccg-project}: ,}#T` |
| – | **Option** | a variable; scoped server / session / window / pane | `set-option [-s|-w] -t <target>` | `base-index 1` is yours (window option) |
| – | **User option** | custom option with `@` prefix | `#{@my-thing}` | `@ccg-project = site` |

### Inspecting in real time

```bash
tmux display-message -p '#{session_name} #{window_index}:#{window_name} pane=#{pane_title}'
tmux show-options -gv window-status-format        # global value
tmux show-options -wv -t <window> @ccg-project    # per-window value
tmux list-windows -t <session> -F '#{window_index} #{window_name} #{pane_title}'
```

## Claude Code

```
┌──────────────────────────────────────────────────────────────────┐
│  ✻ Welcome to Claude Code v2.1.117                               │  ← ⓐ welcome banner (one-shot, on launch)
│                                                                   │
│  ─────────── conversation transcript ───────────                  │  ← ⓑ transcript / message log
│                                                                   │
│  > User message text…                                            │  ← ⓒ user message
│                                                                   │
│  ⏺ Assistant response prose…                                     │  ← ⓓ assistant message
│                                                                   │
│  ● Bash(ls -la)                                                  │  ← ⓔ tool use block (call)
│    ⎿ total 24                                                    │  ← ⓕ tool result block
│      drwxr-xr-x  …                                                │
│                                                                   │
│  ⏺ More assistant prose…                                         │
│                                                                   │
│  ╭──────────────────────────────────────────────────────────────╮ │
│  │ Do you want to allow this?                                   │ │  ← ⓖ permission prompt
│  │ ❯ 1. Yes                                                     │ │     (numbered options, ❯ marks current)
│  │   2. Yes, and don't ask again for this command               │ │
│  │   3. No, and tell Claude what to do differently              │ │
│  ╰──────────────────────────────────────────────────────────────╯ │
│                                                                   │
│  ✳ Streaming…  (esc to interrupt)                                │  ← ⓗ in-flight indicator
│                                                                   │
├──────────────────────────────────────────────────────────────────┤
│ > what you type goes here                                        │  ← ⓘ input prompt
│                                                                   │
│   ⎿  context: 41% used · opus-4-7[1m] · auto-accept · /clear     │  ← ⓙ status line / chrome
└──────────────────────────────────────────────────────────────────┘
            ▲ ⓚ pane_title (sent to tmux): "⠂ <task summary>"
```

| ID | Term | What it is |
|----|------|------------|
| ⓐ | **Welcome banner / startup screen** | Shown on `claude` launch. Version, model, working dir. Disappears once you scroll. |
| ⓑ | **Transcript** (also: conversation, message log) | Append-only log of the conversation. Scrollback works. |
| ⓒ | **User message** / **user turn** | What you sent. |
| ⓓ | **Assistant message** / **assistant turn** | What Claude sent back. Prose between tool calls. |
| ⓔ | **Tool use** / **tool call block** | Claude invoking a tool — `Bash`, `Read`, `Edit`, etc. Tool name + arguments. |
| ⓕ | **Tool result** | Output the tool returned. Often collapsed/truncated by default. |
| ⓖ | **Permission prompt** | The numbered "Do you want to…" overlay when not in auto/yolo mode. `❯` marks the cursor. The strings `Do you want` and `❯ 1.` are what `ccs`'s glyph logic greps for. |
| ⓗ | **In-flight indicator** / **spinner** | The `✳` glyph + `(esc to interrupt)` while a tool call or stream is running. `ccs` greps for `esc to interrupt` for its "active" glyph. |
| ⓘ | **Input prompt** / **composer** | Where you type. Supports multi-line, `/slash` commands, `!shell`, file pasting. |
| ⓙ | **Claude Code status line** | Bottom-of-screen chrome inside the pane: model, context %, mode (plan / accept / auto / yolo), shortcuts. **Different from tmux's status line.** |
| ⓚ | **Pane title Claude sets** | Sent via OSC 2; reflects the current task. Why our `ccg` dashboard splices `#T` so it carries through. |

### Cross-cutting concepts

| Term | Meaning |
|---|---|
| **Session** | One conversation. Has a UUID, can be resumed (`claude -r`) or continued (`claude -c`). |
| **Permission mode** | `default` / `plan` / `acceptEdits` / `bypassPermissions` (yolo). Controls when ⓖ appears. |
| **Slash command** | `/help`, `/clear`, `/loop`, `/ultrareview`, etc. — handled inline. |
| **Skill** | A bundled instruction set the agent loads (e.g. `using-superpowers`). |
| **Subagent** | A Claude instance spawned via the `Task` (or `Agent`) tool with its own isolated context. |
| **MCP server** | External tool provider plugged in via the Model Context Protocol. Tools show up prefixed `mcp__<server>__<tool>`. |
| **Hooks** | Shell commands the harness runs on events (SessionStart, PreToolUse, etc.). Configured in `settings.json`. |
| **Output style** | A persona/format mode (e.g. "concise", "explanatory") set per-session. |

## Confusion-clarifier on the two "status lines"

- **tmux status line** = the bar at ④. Shows windows/sessions.
- **Claude Code status line** = the bar at ⓙ. Shows model/context/mode. Lives *inside* the pane, drawn by Claude.

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
when that option is present, so the source `cc-<name>` sessions (where the
option isn't set) keep their normal tab appearance.
