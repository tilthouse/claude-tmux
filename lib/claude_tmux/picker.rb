# frozen_string_literal: true

module ClaudeTmux
  # `sesh-pick` — wraps `sesh list | fzf | sesh connect` and prepends a
  # glyph derived from `tmux capture-pane` output, so each row shows
  # whether the Claude session is active, waiting on input, idle, or not
  # actually running.
  #
  # Glyph logic is pattern-matching against Claude Code UI strings — if
  # Anthropic rewords them the rules here need updating (they live in one
  # place for that reason).
  class Picker
    GLYPHS = {
      active: '●', # "esc to interrupt" — a tool call is in flight
      waiting: '◐', # "Do you want..." or numbered-option prompt
      idle: '○', # running but nothing in flight
      offline: '·' # sesh entry exists but no tmux session
    }.freeze

    def initialize(tmux: Tmux.new, stderr: $stderr, stdout: $stdout)
      @tmux = tmux
      @stderr = stderr
      @stdout = stdout
    end

    def run
      names = sesh_list
      return 0 if names.empty?

      decorated = names.map { |n| "#{status_for(n)}\t#{n}" }.join("\n")
      selection = fzf_select(decorated)
      return 0 if selection.nil? || selection.empty?

      name = selection.split("\t", 2)[1]
      Kernel.send(:exec, 'sesh', 'connect', name)
    end

    private

    def sesh_list
      out = IO.popen(['sesh', 'list', err: File::NULL], &:read) || ''
      out.each_line.map(&:chomp).reject(&:empty?)
    rescue Errno::ENOENT
      @stderr.puts 'sesh-pick: sesh not found on PATH.'
      []
    end

    def status_for(name)
      return GLYPHS[:offline] unless @tmux.has_session?(name)

      pane = @tmux.capture_pane(name, lines: 30)
      return GLYPHS[:active]  if pane.include?('esc to interrupt')
      return GLYPHS[:waiting] if pane.include?('Do you want') || pane.include?('❯ 1.')

      GLYPHS[:idle]
    end

    def fzf_select(input)
      result = IO.popen(['fzf', '--delimiter=\t', '--with-nth=1,2',
                         '--prompt=sesh> ', '--height=60%', '--reverse'],
                        'r+') do |io|
        io.write(input)
        io.close_write
        io.read
      end
      result&.strip
    rescue Errno::ENOENT
      @stderr.puts 'sesh-pick: fzf not found on PATH.'
      nil
    end
  end
end
