module RoE
  class ModeratedRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override)
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      advisors_list = advisors.to_a
      return [] if advisors_list.empty?

      # Simple implementation: pick advisor based on keyword matching
      # Future: Could use AI to select most relevant advisor
      content = message&.content.to_s.downcase

      scored = advisors_list.map do |advisor|
        score = score_advisor(advisor, content)
        [ advisor, score ]
      end

      # Sort by score descending, return highest scoring advisor
      scored.sort_by { |_, score| -score }.first(1).map(&:first)
    end

    def should_auto_conclude?(conversation)
      conversation.all_advisors_responded?
    end

    private

    def score_advisor(advisor, content)
      score = 0
      score += 10 if content.include?(advisor.name.downcase)

      if advisor.system_prompt.present?
        content_words = content.split
        prompt_words = advisor.system_prompt.downcase.split
        matches = content_words & prompt_words
        score += matches.length * 2
      end

      # Prefer advisors with fewer messages in this conversation
      message_count = @conversation.messages.where(sender: advisor).count
      score -= message_count * 0.5

      score
    end
  end
end
