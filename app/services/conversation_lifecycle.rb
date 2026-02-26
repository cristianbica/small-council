class ConversationLifecycle
  def initialize(conversation)
    @conversation = conversation
    @roe_strategy = RoE::Factory.create(conversation)
    Rails.logger.debug "[ConversationLifecycle] Initialized for conversation #{conversation.id} with RoE: #{conversation.rules_of_engagement}"
  end

  # User posted a message
  # Creates pending messages for responders and enqueues AI jobs
  def user_posted_message(user_message)
    Rails.logger.debug "[ConversationLifecycle#user_posted_message] Processing message #{user_message.id} in conversation #{@conversation.id}"
    return unless user_message.persisted?

    responders = @roe_strategy.determine_responders(user_message)
    Rails.logger.debug "[ConversationLifecycle#user_posted_message] RoE determined #{responders.count} responder(s): #{responders.map { |r| "#{r.name} (ID: #{r.id})" }.join(', ')}"

    responders.each do |advisor|
      Rails.logger.debug "[ConversationLifecycle#user_posted_message] Creating pending message for advisor: #{advisor.name} (ID: #{advisor.id})"
      create_pending_message_and_enqueue(advisor)
    end

    responders
  end

  # AI advisor posted a response
  # Updates message status and triggers any follow-up actions
  def advisor_responded(advisor, content, message)
    Rails.logger.debug "[ConversationLifecycle#advisor_responded] Advisor #{advisor.name} (ID: #{advisor.id}) responded to message #{message.id}"
    return unless message.pending?

    # Update message with response content
    message.update!(
      content: content,
      role: "advisor",
      status: "complete"
    )
    Rails.logger.debug "[ConversationLifecycle#advisor_responded] Message #{message.id} updated with content length: #{content&.length || 0}"

    # Notify RoE strategy for state updates (e.g., round robin tracking)
    @roe_strategy.after_response(advisor)
    Rails.logger.debug "[ConversationLifecycle#advisor_responded] RoE after_response callback executed for #{advisor.name}"

    # Mark advisor as responded for auto-conclusion tracking
    @conversation.mark_advisor_responded(advisor.id)
    Rails.logger.debug "[ConversationLifecycle#advisor_responded] Marked advisor #{advisor.id} as responded. Current responded count: #{@conversation.context['responded_advisor_ids']&.count || 0} / #{@conversation.council.advisors.count}"

    # Broadcast via Turbo Stream
    broadcast_message(message)

    # Check if we should auto-conclude
    Rails.logger.debug "[ConversationLifecycle#advisor_responded] Checking for auto-conclusion..."
    check_for_conclusion

    message
  rescue => e
    handle_error(message, e)
    raise unless e.is_a?(ActiveRecord::RecordInvalid)
  end

  # Check if conversation should auto-conclude
  def check_for_conclusion
    Rails.logger.debug "[ConversationLifecycle#check_for_conclusion] Checking conversation #{@conversation.id} (status: #{@conversation.status}, active?: #{@conversation.active?})"
    return unless @conversation.active?

    should_conclude = @roe_strategy.should_auto_conclude?(@conversation)
    Rails.logger.debug "[ConversationLifecycle#check_for_conclusion] RoE auto-conclude check: #{should_conclude}"

    if should_conclude
      Rails.logger.info "[ConversationLifecycle#check_for_conclusion] Auto-concluding conversation #{@conversation.id}"
      begin_conclusion_process
    else
      Rails.logger.debug "[ConversationLifecycle#check_for_conclusion] Conversation #{@conversation.id} will continue"
    end
  end

  # Begin the conclusion process (status: concluding)
  def begin_conclusion_process
    Rails.logger.info "[ConversationLifecycle#begin_conclusion_process] Starting conclusion for conversation #{@conversation.id}"
    @conversation.update!(status: :concluding)
    Rails.logger.info "[ConversationLifecycle#begin_conclusion_process] Conversation #{@conversation.id} status updated to 'concluding', enqueuing summary job"
    GenerateConversationSummaryJob.perform_later(@conversation.id)
  end

  private

  def create_pending_message_and_enqueue(advisor)
    # For Scribe advisors in Moderated mode, use different placeholder text
    placeholder_content = advisor.scribe? ? "[#{advisor.name}] is selecting an advisor to respond..." : "[#{advisor.name}] is thinking..."

    Rails.logger.debug "[ConversationLifecycle#create_pending_message_and_enqueue] Creating placeholder for #{advisor.name} (scribe: #{advisor.scribe?})"

    placeholder = @conversation.messages.create!(
      account: @conversation.account,
      sender: advisor,
      role: "system",
      content: placeholder_content,
      status: "pending"
    )

    Rails.logger.debug "[ConversationLifecycle#create_pending_message_and_enqueue] Created placeholder message #{placeholder.id}"

    # Broadcast placeholder message
    broadcast_placeholder(placeholder)
    Rails.logger.debug "[ConversationLifecycle#create_pending_message_and_enqueue] Broadcasted placeholder"

    # Enqueue background job to generate actual response
    Rails.logger.info "[ConversationLifecycle#create_pending_message_and_enqueue] Enqueuing job for advisor #{advisor.id}, message #{placeholder.id}"
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
