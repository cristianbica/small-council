# frozen_string_literal: true

module AI
  # Entry point for AI interactions - wraps RubyLLM
  #
  # Design principles:
  # - Stateless tools: Tools are initialized without context
  # - Context injection: context passed at chat() time, flows to tools
  # - No RubyLLM leakage: Returns AI::Model::Response, not RubyLLM types
  # - Automatic tracking: TokenUsage created automatically on every call
  #
  # Example usage:
  #   client = AI::Client.new(
  #     model: advisor.llm_model,
  #     tools: [AI::Tools::Internal::QueryMemoriesTool.new],
  #     system_prompt: advisor.system_prompt
  #   )
  #
  #   response = client.chat(
  #     messages: conversation.messages_for_llm,
  #     context: { space: space, conversation: conversation, user: user }
  #   )
  #   # => AI::Model::Response with usage automatically tracked
  #
  class Client
    class Error < StandardError; end
    class RateLimitError < Error; end
    class APIError < Error; end

    DEFAULT_TEMPERATURE = 0.7
    MAX_RETRIES = 3

    attr_reader :model, :tools, :system_prompt, :temperature

    # Initialize the client
    #
    # @param model [LLMModel] The LLM model to use
    # @param tools [Array<BaseTool>] Array of tool instances (stateless, no context)
    # @param system_prompt [String] System prompt/instructions
    # @param temperature [Float] Temperature for generation (0.0-2.0)
    def initialize(model:, tools: [], system_prompt: nil, temperature: DEFAULT_TEMPERATURE)
      @model = model
      @tools = tools
      @system_prompt = system_prompt
      @temperature = temperature
    end

    # Execute a chat completion
    #
    # @param messages [Array<Hash>] Array of { role: "user|assistant|system", content: String }
    # @param context [Hash] Execution context passed to tools (space, conversation, user, advisor, etc.)
    # @param stream_handler [Proc] Optional streaming handler block
    # @return [AI::Model::Response]
    def chat(messages:, context: {}, &stream_handler)
      with_retry do
        @tool_adapters = []
        ruby_llm_chat = build_ruby_llm_chat

        # Set context on all tool adapters so they can pass it to tools
        @tool_adapters.each { |adapter| adapter.context = context }

        # Add messages to chat
        messages.each do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]
          ruby_llm_chat.add_message(role: role, content: content)
        end

        if stream_handler
          handle_streaming(ruby_llm_chat, stream_handler)
        else
          response = ruby_llm_chat.complete
          track_usage(response, context)
          normalize_response(response)
        end
      end
    rescue RubyLLM::RateLimitError => e
      Rails.logger.error "[AI::Client] Rate limited: #{e.message}"
      raise RateLimitError, "AI service rate limited: #{e.message}"
    rescue RubyLLM::Error => e
      Rails.logger.error "[AI::Client] LLM error: #{e.message}"
      raise APIError, "AI service error: #{e.message}"
      # rescue StandardError => e
      #   Rails.logger.error "[AI::Client] Error: #{e.message}"
      #   raise APIError, "AI service error: #{e.message}"
    end

    # Single-turn completion (convenience method)
    #
    # @param prompt [String] Single user prompt
    # @param context [Hash] Execution context for tools
    # @return [AI::Model::Response]
    def complete(prompt:, context: {})
      chat(messages: [ { role: "user", content: prompt } ], context: context)
    end

    # Get model info from RubyLLM registry
    # @return [RubyLLM::Model::Info, nil]
    def info
      return nil unless model

      RubyLLM.models.find(model.identifier)
    rescue StandardError
      nil
    end

    # Class methods for provider-level operations
    class << self
      # List available models for a provider
      # @param provider [Provider] The provider to list models for
      # @return [Array<Hash>] Array of model data hashes
      def list_models(provider:)
        provider_type = provider.provider_type
        models = RubyLLM.models.by_provider(provider_type.to_sym)

        models.map do |model_info|
          {
            id: model_info.id,
            name: model_info.name,
            provider: model_info.provider,
            capabilities: {
              chat: model_info.type == "chat",
              vision: model_info.supports_vision?,
              json_mode: model_info.structured_output?,
              functions: model_info.supports_functions?
            }
          }
        end
      end

      # Test connection to a provider
      # @param provider [Provider] The provider to test
      # @param test_model_id [String] Model ID to use for testing
      # @return [Hash] { success: true/false, model: String, error: String }
      def test_connection(provider:, test_model_id: nil)
        # Configure RubyLLM for this provider
        RubyLLM.configure do |config|
          case provider.provider_type
          when "openai"
            config.openai_api_key = provider.api_key
            config.openai_organization_id = provider.organization_id if provider.organization_id.present?
          when "openrouter"
            config.openrouter_api_key = provider.api_key
          end
        end

        model_id = test_model_id || find_test_model_id(provider)
        chat = RubyLLM.chat(model: model_id)
        response = chat.ask("Test connection")

        { success: true, model: response.model }
      rescue => e
        { success: false, error: e.message }
      end

      private

      def find_test_model_id(provider)
        # Find first available model for this provider
        models = RubyLLM.models.by_provider(provider.provider_type.to_sym)
        free_model = models.find(&:free?)
        (free_model || models.first)&.id || "gpt-3.5-turbo"
      end
    end

    private

    def build_ruby_llm_chat
      ruby_context = RubyLLM.context do |config|
        configure_provider(config)
      end

      chat = ruby_context.chat(model: model.identifier)
      chat.with_instructions(system_prompt) if system_prompt
      chat.with_temperature(temperature) if temperature

      # Convert tools to adapters and set context on each
      tools.each do |tool|
        adapter = tool.to_ruby_llm_tool
        chat.with_tools(adapter.to_ruby_llm_tool)
        @tool_adapters << adapter
      end

      chat
    end

    def configure_provider(config)
      provider = model.provider

      case provider.provider_type
      when "openai"
        config.openai_api_key = provider.api_key
        config.openai_organization_id = provider.organization_id if provider.organization_id.present?
      when "openrouter"
        config.openrouter_api_key = provider.api_key
      else
        raise APIError, "Unsupported provider type: #{provider.provider_type}"
      end
    end

    def normalize_response(ruby_response)
      tool_calls = ruby_response.tool_calls&.map do |tc|
        AI::Model::ToolCall.new(
          id: tc.id,
          name: tc.name,
          arguments: tc.params || {}
        )
      end || []

      usage = if ruby_response.input_tokens && ruby_response.output_tokens
                AI::Model::TokenUsage.new(
                  input: ruby_response.input_tokens,
                  output: ruby_response.output_tokens
                )
      end

      AI::Model::Response.new(
        content: ruby_response.content || "",
        tool_calls: tool_calls,
        usage: usage,
        raw: ruby_response
      )
    end

    def track_usage(ruby_response, context)
      return unless ruby_response.input_tokens && ruby_response.output_tokens

      account = context[:account] || context[:space]&.account
      return unless account

      conversation = context[:conversation]
      message = context[:message]

      # Calculate cost in cents
      pricing = { input: model.input_price, output: model.output_price }
      usage = AI::Model::TokenUsage.new(
        input: ruby_response.input_tokens,
        output: ruby_response.output_tokens
      )
      cost = usage.estimated_cost(pricing)
      cost_cents = (cost * 100).round

      UsageRecord.create!(
        account: account,
        provider: model.provider.provider_type,
        model: model.identifier,
        input_tokens: ruby_response.input_tokens,
        output_tokens: ruby_response.output_tokens,
        cost_cents: cost_cents,
        message: message,
        recorded_at: Time.current
      )
    rescue => e
      # Log but don't fail the request if tracking fails
      Rails.logger.error "[AI::Client] Failed to track usage: #{e.message}"
    end

    def with_retry(max_attempts: MAX_RETRIES)
      attempts = 0
      begin
        yield
      rescue RubyLLM::RateLimitError => e
        attempts += 1
        if attempts < max_attempts
          sleep_time = 2 ** attempts
          Rails.logger.warn "[AI::Client] Rate limited, retrying in #{sleep_time}s (attempt #{attempts})"
          sleep(sleep_time)
          retry
        end
        raise
      rescue StandardError => e
        attempts += 1
        if attempts < max_attempts && retryable_error?(e)
          sleep(2 ** attempts)
          retry
        end
        raise
      end
    end

    def retryable_error?(error)
      # Retry on transient network errors
      error.is_a?(Net::OpenTimeout) ||
        error.is_a?(Net::ReadTimeout) ||
        error.is_a?(Errno::ECONNRESET) ||
        error.is_a?(Errno::ETIMEDOUT)
    end

    def handle_streaming(ruby_llm_chat, handler)
      accumulated_content = ""
      ruby_llm_chat.complete(streaming: true) do |chunk|
        content = chunk.content
        accumulated_content += content
        handler.call(content)
      end

      # Return a response object (streaming doesn't give us usage data)
      AI::Model::Response.new(
        content: accumulated_content,
        tool_calls: [],
        usage: nil,
        raw: nil
      )
    end
  end
end
