class GenerateAdvisorResponseJob < ApplicationJob
  queue_as :default

  # Job is idempotent - safe to retry
  def perform(advisor_id:, conversation_id:, message_id:)
    Rails.logger.info "[GenerateAdvisorResponseJob] Starting job for advisor_id=#{advisor_id}, conversation_id=#{conversation_id}, message_id=#{message_id}"

    advisor = Advisor.find_by(id: advisor_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)

    Rails.logger.debug "[GenerateAdvisorResponseJob] Loaded objects - advisor: #{advisor&.name || 'NOT FOUND'}, conversation: #{conversation&.id || 'NOT FOUND'}, message: #{message&.id || 'NOT FOUND'}"

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
    Rails.logger.debug "[GenerateAdvisorResponseJob] Set tenant context to account #{advisor.account_id}"

    Rails.logger.info "[GenerateAdvisorResponseJob] Processing message #{message_id} for advisor #{advisor.name} (ID: #{advisor.id})"

    begin
      # Call AI service
      Rails.logger.debug "[GenerateAdvisorResponseJob] Initializing AIClient..."
      client = AIClient.new(advisor: advisor, conversation: conversation, message: message)

      Rails.logger.info "[GenerateAdvisorResponseJob] Calling AI API for advisor #{advisor.name}..."
      result = client.generate_response

      Rails.logger.debug "[GenerateAdvisorResponseJob] AI response received - content length: #{result&.[](:content)&.length || 0}, tokens: #{result&.[](:total_tokens) || 'N/A'}"

      if result && result[:content].present?
        Rails.logger.info "[GenerateAdvisorResponseJob] Successfully got response from AI, delegating to lifecycle"

        # Delegate to ConversationLifecycle for state management
        lifecycle = ConversationLifecycle.new(conversation)
        lifecycle.advisor_responded(advisor, result[:content], message)

        # Record usage
        Rails.logger.debug "[GenerateAdvisorResponseJob] Recording usage..."
        create_usage_record(message, advisor, result)

        Rails.logger.info "[GenerateAdvisorResponseJob] Successfully processed message #{message_id} for advisor #{advisor.name}"
      else
        Rails.logger.error "[GenerateAdvisorResponseJob] Empty response from AI for advisor #{advisor.id}, message #{message.id}"
        handle_error(message, "Empty response from AI - check LLM model configuration")
      end
    rescue AIClient::ApiError => e
      Rails.logger.error "[GenerateAdvisorResponseJob] API Error for advisor #{advisor.id}: #{e.message}"
      handle_error(message, "API Error: #{e.message}")
    rescue => e
      Rails.logger.error "[GenerateAdvisorResponseJob] Unexpected error for advisor #{advisor.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      handle_error(message, "Unexpected error: #{e.message}")
    end
  ensure
    Rails.logger.debug "[GenerateAdvisorResponseJob] Clearing tenant context"
    ActsAsTenant.current_tenant = nil
  end

  private

  def create_usage_record(message, advisor, result)
    model = advisor.effective_llm_model
    return unless model.present?

    UsageRecord.create!(
      account: advisor.account,
      message: message,
      provider: model.provider.provider_type,
      model: model.identifier,
      input_tokens: result[:input_tokens] || 0,
      output_tokens: result[:output_tokens] || 0,
      cost_cents: calculate_cost(model, result),
      recorded_at: Time.current
    )
  end

  def calculate_cost(llm_model, result)
    # Placeholder rates - should be stored in llm_models table
    # OpenAI GPT-4: $0.03/1K input, $0.06/1K output
    # Anthropic Claude: $0.008/1K input, $0.024/1K output

    input_tokens = result[:input_tokens] || 0
    output_tokens = result[:output_tokens] || 0

    # Default rates (dollars per token)
    input_rate = 0.03 / 1000
    output_rate = 0.06 / 1000

    # Adjust for provider
    case llm_model.provider.provider_type
    when "anthropic"
      input_rate = 0.008 / 1000
      output_rate = 0.024 / 1000
    end

    cost_dollars = (input_tokens * input_rate) + (output_tokens * output_rate)
    (cost_dollars * 100).round # Convert to cents
  end

  def broadcast_message(message, conversation)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end

  def handle_error(message, error_content)
    message.update!(
      content: "[Error: #{error_content}]",
      status: "error"
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{message.conversation.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end
end
