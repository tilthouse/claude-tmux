# frozen_string_literal: true

module ClaudeTmux
  class Error < StandardError; end

  class UsageError < Error
    def initialize(message, exit_status: 2)
      super(message)
      @exit_status = exit_status
    end

    attr_reader :exit_status
  end

  class ConfigError < Error; end
end
