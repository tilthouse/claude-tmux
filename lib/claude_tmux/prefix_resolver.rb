# frozen_string_literal: true

module ClaudeTmux
  # Resolve a token against a list of subcommand names by:
  #   1. exact match (always wins)
  #   2. unique prefix from the first character
  # Returns the matched name, nil if no match, or raises UsageError on
  # ambiguity (with the candidate list in the message).
  module PrefixResolver
    module_function

    def resolve(token, names)
      return token if names.include?(token)

      matches = names.select { |n| n.start_with?(token) }
      return nil if matches.empty?
      return matches.first if matches.size == 1

      raise UsageError, "ambiguous: '#{token}' matches #{matches.join(', ')}"
    end
  end
end
