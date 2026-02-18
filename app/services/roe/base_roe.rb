module RoE
  class BaseRoE
    def initialize(conversation)
      @conversation = conversation
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
    end

    # Check if conversation should auto-conclude based on RoE mode
    # Returns: Boolean
    def should_auto_conclude?(conversation)
      false  # Default: no auto-conclude
    end

    protected

    def advisors
      @conversation.council.advisors
    end

    def conversation_history
      @conversation.messages.chronological
    end

    def parse_mentions(content)
      return [] if content.blank?

      mentioned_names = content.scan(/@([a-zA-Z0-9_\-]+)/i).flatten.map(&:downcase)
      return [] if mentioned_names.empty?

      advisors.select do |advisor|
        mentioned_names.any? { |name| name_matches?(advisor, name) }
      end
    end

    def name_matches?(advisor, mention)
      advisor_name_normalized = advisor.name.downcase.gsub(/\s+/, "_")
      advisor_name_normalized == mention.downcase ||
        advisor.name.downcase == mention.downcase
    end
  end
end
