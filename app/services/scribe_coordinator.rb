class ScribeCoordinator
  MENTION_PATTERN = /@([a-zA-Z0-9_]+)/.freeze

  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  # Main entry point: returns array of advisors who should respond
  def determine_responders(last_message: nil)
    # Always check for @mentions first (priority override)
    mentioned = parse_mentions(last_message&.content)
    return mentioned if mentioned.any?

    case conversation.rules_of_engagement.to_sym
    when :round_robin
      next_in_round_robin
    when :moderated
      select_moderated_responder(last_message)
    when :on_demand
      [] # No mentions = no response
    when :silent
      []
    when :consensus
      conversation.council.advisors.to_a
    else
      []
    end
  end

  private

  # Parse @mentions from message content
  def parse_mentions(content)
    return [] if content.blank?

    mentioned_names = content.scan(MENTION_PATTERN).flatten.map(&:downcase)
    return [] if mentioned_names.empty?

    conversation.council.advisors.select do |advisor|
      mentioned_names.include?(advisor.name.downcase.gsub(/\s+/, "_"))
    end
  end

  # Round Robin: return next advisor in sequence
  def next_in_round_robin
    advisors = conversation.council.advisors.order(:id).to_a
    return [] if advisors.empty?

    last_id = conversation.last_advisor_id
    return [ advisors.first ] if last_id.nil?

    last_index = advisors.find_index { |a| a.id.to_s == last_id.to_s }
    next_index = last_index.nil? ? 0 : (last_index + 1) % advisors.count
    [ advisors[next_index] ]
  end

  # Moderated: simple implementation returns advisor with fewest messages
  # (Phase 3: analyze content for relevance matching)
  def select_moderated_responder(last_message)
    advisors = conversation.council.advisors.to_a
    return [] if advisors.empty?

    # Simple: return advisor with fewest messages in this conversation
    # (placeholder for AI-based relevance matching)
    [ advisors.min_by { |a| conversation.messages.where(sender: a).count } ]
  end
end
