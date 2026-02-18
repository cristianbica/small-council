class GenerateAdvisorResponseJob < ApplicationJob
  queue_as :default

  # Job is idempotent - safe to retry
  def perform(advisor_id:, conversation_id:, message_id:)
    advisor = Advisor.find_by(id: advisor_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)

    return unless advisor && conversation && message
    return unless message.pending? # Only process pending messages

    # Set tenant context for background job
    ActsAsTenant.current_tenant = advisor.account

    begin
      # Call AI service
      client = AiClient.new(advisor: advisor, conversation: conversation, message: message)
      result = client.generate_response

      if result && result[:content].present?
        # Update message with response
        message.update!(
          content: result[:content],
          role: "advisor",
          status: "complete"
        )

        # Record usage
        create_usage_record(message, advisor, result)

        # Broadcast via Turbo Stream
        broadcast_message(message, conversation)
      else
        handle_error(message, "Empty response from AI")
      end
    rescue AiClient::ApiError => e
      handle_error(message, "API Error: #{e.message}")
    rescue => e
      handle_error(message, "Unexpected error: #{e.message}")
      Rails.logger.error "[GenerateAdvisorResponseJob] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
    end
  ensure
    ActsAsTenant.current_tenant = nil
  end

  private

  def create_usage_record(message, advisor, result)
    UsageRecord.create!(
      account: advisor.account,
      message: message,
      provider: advisor.llm_model.provider.provider_type,
      model: advisor.llm_model.identifier,
      input_tokens: result[:input_tokens] || 0,
      output_tokens: result[:output_tokens] || 0,
      cost_cents: calculate_cost(advisor.llm_model, result),
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
