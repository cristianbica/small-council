# app/services/conversation_lifecycle.rb
class ConversationLifecycle
  MAX_SCRIBE_INITIATED = 3

  def initialize(conversation)
    @conversation = conversation
    Rails.logger.debug "[ConversationLifecycle] Initialized for conversation #{conversation.id} (type: #{conversation.conversation_type}, roe: #{conversation.roe_type})"
  end

  # Called when user posts a message
  def user_posted_message(user_message)
    Rails.logger.debug "[ConversationLifecycle#user_posted_message] Processing message #{user_message.id}"
    return unless user_message.persisted?

    # Reset scribe initiated count on user message
    @conversation.reset_scribe_initiated_count!

    # Check for commands
    command = CommandParser.parse(user_message.content)
    if command
      handle_command(command, user_message)
      return
    end

    # Normal message flow
    mentioned_advisors = parse_mentions(user_message.content)

    # For Open RoE with @all, expand to all participants (including scribe)
    if should_expand_all_mentions?(user_message)
      mentioned_advisors = @conversation.all_participant_advisors
    end

    # If Open RoE and no mentions, check if conversation has only scribe
    # In that case, assume user wants scribe to respond
    if @conversation.open? && mentioned_advisors.empty? && !user_message.mentions_all?
      non_scribe_advisors = @conversation.participant_advisors
      if non_scribe_advisors.empty?
        # Only scribe in conversation - assume scribe should respond
        Rails.logger.info "[ConversationLifecycle] Only scribe present, auto-triggering scribe response"
        mentioned_advisors = [ @conversation.scribe_advisor ].compact
      else
        Rails.logger.debug "[ConversationLifecycle] Open RoE: no mentions, no advisors will respond"
        return
      end
    end

    # For Consensus and Brainstorming, all advisors respond if no specific mentions
    if (@conversation.consensus? || @conversation.brainstorming?) && mentioned_advisors.empty?
      mentioned_advisors = @conversation.all_participant_advisors
    end

    # Populate pending_advisor_ids on the message
    user_message.update!(pending_advisor_ids: mentioned_advisors.map(&:id))

    # Create pending responses for each advisor
    mentioned_advisors.each do |advisor|
      create_pending_message_and_enqueue(advisor, user_message)
    end

    mentioned_advisors
  end

  # Called when advisor responds (via job completion)
  def advisor_responded(advisor_response_message)
    parent_message = advisor_response_message.parent_message
    return unless parent_message

    Rails.logger.debug "[ConversationLifecycle#advisor_responded] Advisor #{advisor_response_message.sender.name} responded to message #{parent_message.id}"

    # Remove advisor from pending list
    parent_message.resolve_for_advisor!(advisor_response_message.sender_id)

    # Broadcast the completed response
    broadcast_message(advisor_response_message)

    # Check if parent is now solved
    if parent_message.solved?
      Rails.logger.debug "[ConversationLifecycle] Message #{parent_message.id} is now solved"
      handle_message_solved(parent_message)
    end
  end

  # Handle error during advisor response generation
  def advisor_response_error(message, error_content)
    Rails.logger.error "[ConversationLifecycle] Error in advisor response: #{error_content}"

    message.update!(
      content: "[Error: #{error_content}]",
      status: "error"
    )

    # Remove from pending to prevent blocking
    if message.parent_message
      message.parent_message.resolve_for_advisor!(message.sender_id)
    end

    broadcast_message(message)
  end

  # Begin the conclusion process
  def begin_conclusion_process
    Rails.logger.info "[ConversationLifecycle] Starting conclusion for conversation #{@conversation.id}"
    @conversation.update!(status: :concluding)
    GenerateConversationSummaryJob.perform_later(@conversation.id)
  end

  private

  def handle_message_solved(message)
    # Only handle root messages (not replies) for scribe follow-up
    return unless message.root_message?

    # Check scribe initiated limit
    if @conversation.scribe_initiated_count >= MAX_SCRIBE_INITIATED
      Rails.logger.debug "[ConversationLifecycle] Scribe initiated limit reached (#{@conversation.scribe_initiated_count}/#{MAX_SCRIBE_INITIATED})"
      return
    end

    # Get scribe advisor
    scribe = @conversation.scribe_advisor
    return unless scribe

    # Create scribe follow-up message
    scribe_message = @conversation.messages.create!(
      account: @conversation.account,
      sender: scribe,
      role: "advisor",
      content: "[Scribe is evaluating...]",
      status: "pending"
    )

    @conversation.increment_scribe_initiated_count!

    Rails.logger.info "[ConversationLifecycle] Scribe follow-up created (message #{scribe_message.id}, count: #{@conversation.scribe_initiated_count}/#{MAX_SCRIBE_INITIATED})"

    GenerateAdvisorResponseJob.perform_later(
      advisor_id: scribe.id,
      conversation_id: @conversation.id,
      message_id: scribe_message.id,
      is_scribe_followup: true
    )
  end

  def handle_command(command, user_message)
    user = user_message.sender

    unless command.valid?
      create_system_message("Command error: #{command.errors.join(', ')}")
      return
    end

    result = command.execute(conversation: @conversation, user: user)
    create_system_message(result[:message])

    # Also broadcast the command result
    broadcast_system_message(result[:message])
  end

  def create_pending_message_and_enqueue(advisor, parent_message)
    # Check depth limit
    current_depth = parent_message.depth + 1
    max_depth = @conversation.max_depth

    Rails.logger.debug "[ConversationLifecycle] Creating pending message for #{advisor.name} (depth: #{current_depth}, max: #{max_depth})"

    if current_depth > max_depth
      Rails.logger.debug "[ConversationLifecycle] Depth limit reached (#{current_depth} > #{max_depth}), skipping #{advisor.name}"
      return nil
    end

    placeholder = @conversation.messages.create!(
      account: @conversation.account,
      sender: advisor,
      role: "system",
      parent_message: parent_message,
      content: "[#{advisor.name}] is thinking...",
      status: "pending"
    )

    Rails.logger.debug "[ConversationLifecycle] Created placeholder message #{placeholder.id}"

    # Broadcast placeholder
    broadcast_placeholder(placeholder)

    # Enqueue job
    GenerateAdvisorResponseJob.perform_later(
      advisor_id: advisor.id,
      conversation_id: @conversation.id,
      message_id: placeholder.id
    )

    placeholder
  end

  def parse_mentions(content)
    return [] if content.blank?

    mentioned_names = content.scan(/@([a-zA-Z0-9_\-]+)/i).flatten.map(&:downcase)

    # Filter out 'all' and 'everyone' as they're handled separately
    mentioned_names.reject! { |name| name == "all" || name == "everyone" }

    @conversation.all_participant_advisors.select do |advisor|
      mentioned_names.any? { |name| name_matches?(advisor, name) }
    end
  end

  def name_matches?(advisor, mention)
    advisor_name_normalized = advisor.name.downcase.gsub(/[\s\-]+/, "_")
    mention_normalized = mention.downcase.gsub(/[\s\-]+/, "_")

    advisor_name_normalized == mention_normalized ||
      advisor.name.downcase.include?(mention.downcase)
  end

  def should_expand_all_mentions?(message)
    message.mentions_all?
  end

  def create_system_message(content)
    @conversation.messages.create!(
      account: @conversation.account,
      sender: @conversation.user,  # System messages attributed to conversation owner
      role: "system",
      content: content,
      status: "complete"
    )
  end

  def broadcast_message(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{@conversation.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end

  def broadcast_placeholder(message)
    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{@conversation.id}",
      target: "messages",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end

  def broadcast_system_message(content)
    message = create_system_message(content)
    broadcast_placeholder(message)
  end
end
