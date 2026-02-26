module RoE
  class BaseRoE
    def initialize(conversation)
      @conversation = conversation
      Rails.logger.debug "[RoE::BaseRoE] Initialized #{self.class} for conversation #{conversation.id}"
    end

    # Must implement: given a message, which advisors respond?
    # Returns: Array of Advisor objects
    def determine_responders(message)
      raise NotImplementedError, "#{self.class} must implement determine_responders"
    end

    # Optional: called after each advisor response
    # Used by RoundRobinRoE to update state
    def after_response(advisor)
      # Override in subclasses if needed
      Rails.logger.debug "[RoE::BaseRoE#after_response] Default callback for advisor #{advisor.name} (ID: #{advisor.id}) - no action taken"
    end

    # Check if conversation should auto-conclude based on RoE mode
    # Returns: Boolean
    def should_auto_conclude?(conversation)
      Rails.logger.debug "[RoE::BaseRoE#should_auto_conclude?] Default: false for #{self.class}"
      false  # Default: no auto-conclude
    end

    protected

    def advisors
      advisors_list = @conversation.council.advisors
      Rails.logger.debug "[RoE::#{self.class}] Available advisors in council: #{advisors_list.count} - #{advisors_list.map { |a| "#{a.name} (ID: #{a.id})" }.join(', ')}"
      advisors_list
    end

    def conversation_history
      messages = @conversation.messages.chronological
      Rails.logger.debug "[RoE::#{self.class}] Conversation history: #{messages.count} messages"
      messages
    end

    def parse_mentions(content)
      Rails.logger.debug "[RoE::#{self.class}#parse_mentions] Parsing content: '#{content}'"
      return [] if content.blank?

      mentioned_names = content.scan(/@([a-zA-Z0-9_\-]+)/i).flatten.map(&:downcase)
      Rails.logger.debug "[RoE::#{self.class}#parse_mentions] Found @mentions: #{mentioned_names.inspect}"
      return [] if mentioned_names.empty?

      all_advisors = advisors.to_a
      mentioned_advisors = all_advisors.select do |advisor|
        matches = mentioned_names.any? { |name| name_matches?(advisor, name) }
        Rails.logger.debug "[RoE::#{self.class}#parse_mentions] Checking advisor '#{advisor.name}' against mentions: #{matches ? 'MATCH' : 'no match'}"
        matches
      end

      Rails.logger.debug "[RoE::#{self.class}#parse_mentions] Parsed #{mentioned_advisors.count} mentioned advisor(s): #{mentioned_advisors.map(&:name).join(', ')}"
      mentioned_advisors
    end

    def name_matches?(advisor, mention)
      advisor_name_normalized = advisor.name.downcase.gsub(/\s+/, "_")
      normalized_match = advisor_name_normalized == mention.downcase
      direct_match = advisor.name.downcase == mention.downcase

      Rails.logger.debug "[RoE::#{self.class}#name_matches?] Comparing '#{advisor.name}' with mention '@#{mention}' - normalized: '#{advisor_name_normalized}' == '#{mention.downcase}' => #{normalized_match}, direct: #{direct_match}"

      normalized_match || direct_match
    end
  end
end
