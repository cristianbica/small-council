module RoE
  class ModeratedRoE < BaseRoE
    def determine_responders(message)
      Rails.logger.debug "[RoE::ModeratedRoE#determine_responders] Starting for message #{message.id}: '#{message.content}'"

      # Check for @mentions first (priority override)
      Rails.logger.debug "[RoE::ModeratedRoE#determine_responders] Step 1: Checking for @mentions..."
      mentioned = parse_mentions(message&.content)

      # Filter out Scribe from mentions - Scribe doesn't respond directly, it moderates
      non_scribe_mentions = mentioned.reject(&:scribe?)
      Rails.logger.debug "[RoE::ModeratedRoE#determine_responders] Filtered mentions: #{mentioned.count} total, #{non_scribe_mentions.count} non-Scribe"

      # If user mentioned specific advisors (not Scribe), those advisors respond
      if non_scribe_mentions.any?
        Rails.logger.info "[RoE::ModeratedRoE#determine_responders] User mentioned specific advisors: #{non_scribe_mentions.map(&:name).join(', ')} - bypassing Scribe moderation"
        return non_scribe_mentions
      end

      advisors_list = advisors.to_a
      if advisors_list.empty?
        Rails.logger.warn "[RoE::ModeratedRoE#determine_responders] No advisors available in council!"
        return []
      end

      # Use the space's Scribe advisor for moderation
      Rails.logger.debug "[RoE::ModeratedRoE#determine_responders] Step 2: Looking for Scribe advisor..."
      scribe = @conversation.council.scribe_advisor

      if scribe.present?
        Rails.logger.info "[RoE::ModeratedRoE#determine_responders] Using Scribe '#{scribe.name}' (ID: #{scribe.id}) for moderation"
        return [ scribe ]
      end

      # Fall back to keyword-based selection if scribe is unavailable
      Rails.logger.warn "[RoE::ModeratedRoE#determine_responders] No Scribe found! Falling back to keyword-based selection"
      content = message&.content.to_s.downcase

      scored = advisors_list.map do |advisor|
        score = score_advisor(advisor, content)
        [ advisor, score ]
      end

      # Sort by score descending, return highest scoring advisor
      best_match = scored.sort_by { |_, score| -score }.first
      Rails.logger.info "[RoE::ModeratedRoE#determine_responders] Keyword selection: #{best_match.first.name} (score: #{best_match.last})"
      [ best_match.first ]
    end

    def should_auto_conclude?(conversation)
      result = conversation.all_advisors_responded?
      responded_count = conversation.context["responded_advisor_ids"]&.count || 0
      total_advisors = conversation.council.advisors.count
      Rails.logger.debug "[RoE::ModeratedRoE#should_auto_conclude?] Moderated mode auto-conclude check: #{result} (#{responded_count}/#{total_advisors} responded)"
      result
    end

    private

    def score_advisor(advisor, content)
      score = 0
      name_match = content.include?(advisor.name.downcase)
      score += 10 if name_match
      Rails.logger.debug "[RoE::ModeratedRoE#score_advisor] Advisor '#{advisor.name}': name match = #{name_match}, base score = #{score}"

      if advisor.system_prompt.present?
        content_words = content.split
        prompt_words = advisor.system_prompt.downcase.split
        matches = content_words & prompt_words
        keyword_score = matches.length * 2
        score += keyword_score
        Rails.logger.debug "[RoE::ModeratedRoE#score_advisor] Advisor '#{advisor.name}': keyword matches = #{matches.length}, keyword score = #{keyword_score}"
      end

      # Prefer advisors with fewer messages in this conversation
      message_count = @conversation.messages.where(sender: advisor).count
      participation_penalty = message_count * 0.5
      score -= participation_penalty
      Rails.logger.debug "[RoE::ModeratedRoE#score_advisor] Advisor '#{advisor.name}': message count = #{message_count}, penalty = #{participation_penalty}, final score = #{score}"

      score
    end
  end
end
