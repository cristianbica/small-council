module RoE
  class Factory
    ROE_MAP = {
      "round_robin" => RoundRobinRoE,
      "moderated" => ModeratedRoE,
      "on_demand" => OnDemandRoE,
      "silent" => SilentRoE,
      "consensus" => ConsensusRoE
    }.freeze

    def self.create(conversation)
      roe_class = ROE_MAP[conversation.rules_of_engagement]
      roe_class ||= SilentRoE # Default fallback
      roe_class.new(conversation)
    end
  end
end
