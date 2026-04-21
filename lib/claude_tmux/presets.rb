# frozen_string_literal: true

module ClaudeTmux
  # Maps option values to claude CLI flag arrays.
  #
  # After the v0.3 CLI restructure, presets are no longer positional
  # barewords; they're option values (`--permission plan`, `--model sonnet`,
  # `--yolo`). This module is the single value→flag mapping used by both
  # project and group modes.
  module Presets
    VALID_PERMISSIONS = %w[plan accept auto].freeze
    VALID_MODELS      = %w[opus sonnet].freeze

    module_function

    def permission_flags(mode)
      return [] if mode.nil?

      case mode
      when 'plan', 'auto' then ['--permission-mode', mode]
      when 'accept'       then ['--permission-mode', 'acceptEdits']
      else raise ArgumentError, "invalid permission mode: #{mode.inspect}"
      end
    end

    def model_flags(model)
      return [] if model.nil?
      raise ArgumentError, "invalid model: #{model.inspect}" unless VALID_MODELS.include?(model)

      ['--model', model]
    end

    def yolo_flags(yolo)
      yolo ? ['--dangerously-skip-permissions'] : []
    end

    # Convenience: combine all three into a flat flag list.
    def all_flags(permission:, model:, yolo:)
      permission_flags(permission) + model_flags(model) + yolo_flags(yolo)
    end
  end
end
