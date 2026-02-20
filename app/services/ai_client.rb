class AiClient
  class Error < StandardError; end
  class ApiError < Error; end
  class RateLimitError < Error; end
  class InvalidResponseError < Error; end

  MAX_RETRIES = 2
  RETRY_DELAY = 1 # seconds

  attr_reader :advisor, :conversation, :message

  def initialize(advisor:, conversation:, message:)
    @advisor = advisor
    @conversation = conversation
    @message = message
  end

  # Main entry point: calls LLM API and returns response content
  def generate_response
    return nil unless advisor.llm_model.present?
    return nil unless advisor.llm_model.enabled?

    with_retries do
      # Use the new unified client: model_instance.api.chat(...)
      result = advisor.llm_model.api.chat(
        build_messages,
        system_prompt: advisor.system_prompt,
        temperature: advisor.model_config["temperature"] || 0.7,
        max_tokens: advisor.model_config["max_tokens"] || 1000
      )

      result
    end
  rescue LLM::APIError => e
    log_error(e)
    raise ApiError, "AI API call failed: #{e.message}"
  rescue => e
    log_error(e)
    raise ApiError, "Unexpected error: #{e.message}"
  end

  private

  def build_messages
    conversation.messages.chronological.filter_map do |msg|
      next if msg.id == message.id # Skip the pending message itself

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      { role: role, content: msg.content }
    end
  end

  def with_retries
    retries = 0
    begin
      yield
    rescue StandardError => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(RETRY_DELAY * retries)
        retry
      else
        raise
      end
    end
  end

  def log_error(error)
    Rails.logger.error "[AiClient] Error for advisor #{advisor.id}: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n") if error.backtrace
  end
end
