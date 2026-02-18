module RoE
  class RoundRobinRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override)
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      # Get next advisor in sequence
      advisors_list = advisors.order(:id).to_a
      return [] if advisors_list.empty?

      last_spoken = @conversation.last_advisor_id

      next_index = if last_spoken
        last_index = advisors_list.find_index { |a| a.id.to_s == last_spoken.to_s }
        last_index ? (last_index + 1) % advisors_list.length : 0
      else
        0
      end

      [ advisors_list[next_index] ]
    end

    def after_response(advisor)
      # Update last_advisor_id in conversation context
      @conversation.mark_advisor_spoken(advisor.id)
    end

    def should_auto_conclude?(conversation)
      return false if conversation.council.advisors.empty?

      responded_count = conversation.context["responded_advisor_ids"]&.count || 0
      responded_count >= conversation.council.advisors.count
    end
  end
end
