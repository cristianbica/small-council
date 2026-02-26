module RoE
  class RoundRobinRoE < BaseRoE
    def determine_responders(message)
      Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Starting for message #{message.id}: '#{message.content}'"

      # Check for @mentions first (priority override)
      Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Step 1: Checking for @mentions..."
      mentioned = parse_mentions(message&.content)

      if mentioned.any?
        Rails.logger.info "[RoE::RoundRobinRoE#determine_responders] User mentioned specific advisors: #{mentioned.map(&:name).join(', ')} - bypassing round robin"
        return mentioned
      end

      # Get next advisor in sequence
      Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Step 2: Determining next advisor in round robin..."
      advisors_list = advisors.order(:id).to_a

      if advisors_list.empty?
        Rails.logger.warn "[RoE::RoundRobinRoE#determine_responders] No advisors available!"
        return []
      end

      last_spoken = @conversation.last_advisor_id
      Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Last spoken advisor ID: #{last_spoken || 'none (first message)'}"

      next_index = if last_spoken
        last_index = advisors_list.find_index { |a| a.id.to_s == last_spoken.to_s }
        calculated_index = last_index ? (last_index + 1) % advisors_list.length : 0
        Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Last index: #{last_index}, next index: #{calculated_index}"
        calculated_index
      else
        Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] No last advisor, starting from index 0"
        0
      end

      selected_advisor = advisors_list[next_index]
      Rails.logger.info "[RoE::RoundRobinRoE#determine_responders] Selected advisor: #{selected_advisor.name} (ID: #{selected_advisor.id}, index: #{next_index}/#{advisors_list.length})"
      [ selected_advisor ]
    end

    def after_response(advisor)
      # Update last_advisor_id in conversation context
      Rails.logger.debug "[RoE::RoundRobinRoE#after_response] Marking advisor #{advisor.name} (ID: #{advisor.id}) as having spoken"
      @conversation.mark_advisor_spoken(advisor.id)
      Rails.logger.debug "[RoE::RoundRobinRoE#after_response] Updated last_advisor_id to #{advisor.id}"
    end

    def should_auto_conclude?(conversation)
      return false if conversation.council.advisors.empty?

      responded_count = conversation.context["responded_advisor_ids"]&.count || 0
      total_advisors = conversation.council.advisors.count
      result = responded_count >= total_advisors

      Rails.logger.debug "[RoE::RoundRobinRoE#should_auto_conclude?] Round robin auto-conclude check: #{result} (#{responded_count}/#{total_advisors} responded)"
      Rails.logger.debug "[RoE::RoundRobinRoE#should_auto_conclude?] Responded IDs: #{conversation.context['responded_advisor_ids'].inspect}"
      result
    end
  end
end
