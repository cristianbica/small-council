module RoE
  class OnDemandRoE < BaseRoE
    def determine_responders(message)
      # Parse @mentions from message content
      parse_mentions(message&.content)
    end
  end
end
