# frozen_string_literal: true

module ClaudeTmux
  # Prompt: thin abstraction over fzf and tty input so ConfigTui can be
  # exercised in tests via FakePrompt without spawning real fzf processes.
  #
  # Every method returns plain Ruby data (no fzf-specific shapes leak out):
  #   #choose  → { key: <pressed-expect-key or nil>, item: <selected line or nil>, query: <typed query or nil> }
  #              `nil` item on ESC; `key: nil` means Enter (or no expect: was set).
  #   #input   → typed string (nil on ESC/EOF)
  #   #confirm → true/false
  class Prompt
    def initialize(stderr: $stderr)
      @stderr = stderr
    end

    def choose(items, header:, expect: [], print_query: false)
      args = ['fzf', '--prompt', '> ', '--header', header, '--reverse', '--height=60%']
      args += ['--expect', expect.join(',')] unless expect.empty?
      args << '--print-query' if print_query
      out = IO.popen(args, 'r+') do |io|
        io.write(items.join("\n"))
        io.close_write
        io.read
      end
      return { key: nil, item: nil, query: nil } if out.nil?

      lines = out.each_line.map(&:chomp)
      query = print_query ? lines.shift : nil
      key = nil
      unless expect.empty?
        key = lines.shift
        key = nil if key.nil? || key.empty?
      end
      { key: key, item: lines.first, query: query }
    rescue Errno::ENOENT
      @stderr.puts 'ccg: fzf not found on PATH — install fzf to use ccg config.'
      { key: nil, item: nil, query: nil }
    end

    def input(label:)
      @stderr.print("#{label} ")
      File.open('/dev/tty', 'r') { |io| io.gets&.chomp }
    end

    def confirm(label:)
      response = input(label: "#{label} (y/n)")
      response&.downcase&.start_with?('y') || false
    end
  end

  # Test double: queue of {method:, value:} responses. Pop one per call;
  # raise if the queue is empty or the method doesn't match.
  class FakePrompt
    attr_reader :log

    def initialize(responses: [])
      @responses = responses.dup
      @log = []
    end

    def choose(items, header:, expect: [], print_query: false)
      pop(:choose, items: items, header: header, expect: expect, print_query: print_query)
    end

    def input(label:)
      pop(:input, label: label)
    end

    def confirm(label:)
      pop(:confirm, label: label)
    end

    private

    def pop(method, args)
      raise "FakePrompt: no scripted response for #{method}" if @responses.empty?

      head = @responses.shift
      raise "FakePrompt: expected #{head[:method]}, got #{method}" unless head[:method] == method

      @log << { method: method, args: args, returned: head[:value] }
      head[:value]
    end
  end
end
