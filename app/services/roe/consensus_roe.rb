module RoE
  class ConsensusRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override)
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      # All advisors respond
      advisors.to_a
    end

    def should_auto_conclude?(conversation)
      conversation.all_advisors_responded?
    end
  end
end
