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

    provider_type = advisor.llm_model.provider.provider_type.to_sym

    case provider_type
    when :openai
      call_openai
    when :anthropic
      call_anthropic
    when :github
      call_github_models
    else
      raise Error, "Unsupported provider: #{provider_type}"
    end
  rescue => e
    log_error(e)
    raise ApiError, "AI API call failed: #{e.message}"
  end

  private

  def call_openai
    client = OpenAI::Client.new(
      access_token: advisor.llm_model.provider.api_key,
      organization_id: advisor.llm_model.provider.organization_id
    )

    with_retries do
      response = client.chat(
        parameters: {
          model: advisor.llm_model.identifier,
          messages: build_messages,
          temperature: advisor.model_config["temperature"] || 0.7,
          max_tokens: advisor.model_config["max_tokens"] || 1000
        }
      )

      parse_openai_response(response)
    end
  end

  def call_anthropic
    client = Anthropic::Client.new(
      access_token: advisor.llm_model.provider.api_key
    )

    with_retries do
      response = client.messages(
        parameters: {
          model: advisor.llm_model.identifier,
          messages: build_messages_for_anthropic,
          system: advisor.system_prompt,
          max_tokens: advisor.model_config["max_tokens"] || 1000
        }
      )

      parse_anthropic_response(response)
    end
  end

  def call_github_models
    # GitHub Models uses OpenAI-compatible API endpoint
    client = OpenAI::Client.new(
      access_token: advisor.llm_model.provider.api_key,
      uri_base: "https://models.inference.ai.azure.com"
    )

    with_retries do
      response = client.chat(
        parameters: {
          model: advisor.llm_model.identifier,
          messages: build_messages,
          temperature: advisor.model_config["temperature"] || 0.7,
          max_tokens: advisor.model_config["max_tokens"] || 1000
        }
      )

      parse_openai_response(response)
    end
  end

  def build_messages
    messages = []
    messages << { role: "system", content: advisor.system_prompt }

    conversation.messages.chronological.each do |msg|
      next if msg.id == message.id # Skip the pending message itself

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      messages << { role: role, content: msg.content }
    end

    messages
  end

  def build_messages_for_anthropic
    # Anthropic uses different message format (no system message in array)
    conversation.messages.chronological.filter_map do |msg|
      next if msg.id == message.id

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      { role: role, content: msg.content }
    end
  end

  def parse_openai_response(response)
    choice = response.dig("choices", 0)
    content = choice.dig("message", "content")
    usage = response["usage"]

    {
      content: content,
      input_tokens: usage["prompt_tokens"],
      output_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"]
    }
  end

  def parse_anthropic_response(response)
    content = response.dig("content", 0, "text")
    usage = response["usage"]

    {
      content: content,
      input_tokens: usage["input_tokens"],
      output_tokens: usage["output_tokens"],
      total_tokens: usage["input_tokens"] + usage["output_tokens"]
    }
  end

  def with_retries
    retries = 0
    begin
      yield
    rescue => e
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
