module RoE
  class SilentRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override even in silent mode)
      # This allows users to force a response by mentioning
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      [] # No one responds otherwise
    end
  end
end
