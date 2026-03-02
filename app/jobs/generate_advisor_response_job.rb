class GenerateAdvisorResponseJob < ApplicationJob
  queue_as :default

  # Job is idempotent - safe to retry
  def perform(advisor_id:, conversation_id:, message_id:, is_scribe_followup: false)
    Rails.logger.info "[GenerateAdvisorResponseJob] Starting job for advisor_id=#{advisor_id}, conversation_id=#{conversation_id}, message_id=#{message_id}, scribe_followup=#{is_scribe_followup}"

    advisor = Advisor.find_by(id: advisor_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)

    unless advisor && conversation && message
      Rails.logger.error "[GenerateAdvisorResponseJob] Missing required objects: advisor=#{advisor.present?}, conversation=#{conversation.present?}, message=#{message.present?}"
      return
    end

    if message.cancelled?
      Rails.logger.info "[GenerateAdvisorResponseJob] Message #{message_id} was cancelled, skipping"
      return
    end

    unless message.pending?
      Rails.logger.info "[GenerateAdvisorResponseJob] Message #{message_id} is not pending (status: #{message.status}), skipping"
      return
    end

    # Set tenant context for background job
    ActsAsTenant.current_tenant = advisor.account

    # Set space context for conversation
    Current.space = conversation.space || advisor.space || conversation.advisors.where.not(space: nil).first&.space

    Rails.logger.info "[GenerateAdvisorResponseJob] Processing message #{message_id} for advisor #{advisor.name} (space: #{Current.space&.id || 'nil'})"

    begin
      # Generate response based on advisor type
      if advisor.scribe?
        response = generate_scribe_response(advisor, conversation, message, is_scribe_followup)
      else
        response = generate_advisor_response(advisor, conversation, message)
      end

      if response.content.present?
        Rails.logger.info "[GenerateAdvisorResponseJob] Successfully got response, updating message #{message_id}"

        # Update message with response
        message.update!(
          content: response.content,
          role: "advisor",
          status: "complete"
        )

        # Delegate to ConversationLifecycle for follow-up handling
        lifecycle = ConversationLifecycle.new(conversation)
        lifecycle.advisor_responded(message)

        Rails.logger.info "[GenerateAdvisorResponseJob] Successfully processed message #{message_id}"
      else
        Rails.logger.error "[GenerateAdvisorResponseJob] Empty response from AI for advisor #{advisor.id}"
        handle_error(message, lifecycle, "Empty response from AI")
      end
    rescue AI::ContentGenerator::NoModelError => e
      Rails.logger.error "[GenerateAdvisorResponseJob] No Model Error: #{e.message}"
      handle_error(message, lifecycle, "No AI Model: #{e.message}")
    rescue AI::Client::APIError => e
      Rails.logger.error "[GenerateAdvisorResponseJob] API Error: #{e.message}"
      handle_error(message, lifecycle, "API Error: #{e.message}")
    rescue => e
      Rails.logger.error "[GenerateAdvisorResponseJob] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      handle_error(message, lifecycle, "Unexpected error: #{e.message}")
    end
  ensure
    ActsAsTenant.current_tenant = nil
    Current.space = nil
  end

  private

  def generate_advisor_response(advisor, conversation, message)
    generator = AI::ContentGenerator.new
    generator.generate_advisor_response(
      advisor: advisor,
      conversation: conversation,
      parent_message: message.parent_message,
      context: { message: message }
    )
  end

  def generate_scribe_response(advisor, conversation, message, is_scribe_followup)
    generator = AI::ContentGenerator.new

    if is_scribe_followup
      generator.generate_scribe_followup(
        advisor: advisor,
        conversation: conversation,
        message: message,
        context: { message: message }
      )
    else
      generator.generate_advisor_response(
        advisor: advisor,
        conversation: conversation,
        parent_message: message.parent_message,
        context: { message: message }
      )
    end
  end

  def handle_error(message, lifecycle, error_content)
    message.update!(
      content: "[Error: #{error_content}]",
      status: "error"
    )

    lifecycle&.advisor_response_error(message, error_content)

    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{message.conversation.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end
end
