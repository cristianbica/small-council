class ConversationLifecycle
  def initialize(conversation)
    @conversation = conversation
    @roe_strategy = RoE::Factory.create(conversation)
  end

  # User posted a message
  # Creates pending messages for responders and enqueues AI jobs
  def user_posted_message(user_message)
    return unless user_message.persisted?

    responders = @roe_strategy.determine_responders(user_message)

    responders.each do |advisor|
      create_pending_message_and_enqueue(advisor)
    end

    responders
  end

  # AI advisor posted a response
  # Updates message status and triggers any follow-up actions
  def advisor_responded(advisor, content, message)
    return unless message.pending?

    # Update message with response content
    message.update!(
      content: content,
      role: "advisor",
      status: "complete"
    )

    # Notify RoE strategy for state updates (e.g., round robin tracking)
    @roe_strategy.after_response(advisor)

    # Mark advisor as responded for auto-conclusion tracking
    @conversation.mark_advisor_responded(advisor.id)

    # Broadcast via Turbo Stream
    broadcast_message(message)

    # Check if we should auto-conclude
    check_for_conclusion

    message
  rescue => e
    handle_error(message, e)
    raise unless e.is_a?(ActiveRecord::RecordInvalid)
  end

  # Check if conversation should auto-conclude
  def check_for_conclusion
    return unless @conversation.active?

    if @roe_strategy.should_auto_conclude?(@conversation)
      begin_conclusion_process
    end
  end

  # Begin the conclusion process (status: concluding)
  def begin_conclusion_process
    @conversation.update!(status: :concluding)
    GenerateConversationSummaryJob.perform_later(@conversation.id)
  end

  private

  def create_pending_message_and_enqueue(advisor)
    placeholder = @conversation.messages.create!(
      account: @conversation.account,
      sender: advisor,
      role: "system",
      content: "[#{advisor.name}] is thinking...",
      status: "pending"
    )

    # Broadcast placeholder message
    broadcast_placeholder(placeholder)

    # Enqueue background job to generate actual response
    GenerateAdvisorResponseJob.perform_later(
      advisor_id: advisor.id,
      conversation_id: @conversation.id,
      message_id: placeholder.id
    )

    placeholder
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

  def handle_error(message, error)
    Rails.logger.error "[ConversationLifecycle] Error in advisor_responded: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")

    message.update!(
      content: "[Error: #{error.message}]",
      status: "error"
    )

    broadcast_message(message)
  end
end
