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
        ruby_llm_chat = build_ruby_llm_chat(context: context)

        # Set context on all tool adapters so they can pass it to tools
        @tool_adapters.each { |adapter| adapter.context = context }

        council_context_message = build_council_context_message(context)
        if council_context_message.present?
          ruby_llm_chat.add_message(role: "system", content: council_context_message)
        end

        memory_index_message = build_memory_index_context_message(context)
        if memory_index_message.present?
          ruby_llm_chat.add_message(role: "system", content: memory_index_message)
        end

        tool_policy_message = build_tool_policy_context_message(context, messages)
        if tool_policy_message.present?
          ruby_llm_chat.add_message(role: "system", content: tool_policy_message)
        end

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

    def build_ruby_llm_chat(context: {})
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

      # Register ModelInteraction recording via event handlers
      register_interaction_handler(chat, context)

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

    def register_interaction_handler(chat, context)
      message = context[:message]
      account = context[:account] || context[:space]&.account
      return unless message && account

      recorder = AI::ModelInteractionRecorder.new(
        message_id: message.id,
        account_id: account.id
      )
      recorder.start_timing

      chat.on_end_message do |response|
        recorder.record_chat(chat: chat, response: response)
      end

      chat.on_tool_call do |tool_call|
        recorder.record_tool_call(tool_call)
      end

      chat.on_tool_result do |result|
        recorder.record_tool_result(result)
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

    def build_memory_index_context_message(context)
      memory_index = context[:memory_index]
      return nil unless memory_index.is_a?(Hash)

      primary_summary = memory_index[:primary_summary]
      knowledge_entries = memory_index[:knowledge_entries]

      has_primary_summary = primary_summary.is_a?(Hash)
      has_knowledge_entries = knowledge_entries.respond_to?(:any?) && knowledge_entries.any?
      return nil unless has_primary_summary || has_knowledge_entries

      lines = [ "Memory index (curated):" ]

      if has_primary_summary
        lines << "Primary summary:"
        lines << "- id: #{primary_summary[:id] || primary_summary['id']}"
        lines << "- title: #{primary_summary[:title] || primary_summary['title']}"
        lines << "- summary_excerpt_50_words: #{primary_summary[:summary_excerpt_50_words] || primary_summary['summary_excerpt_50_words']}"
      end

      if has_knowledge_entries
        lines << "Knowledge entries:"
        knowledge_entries.each_with_index do |entry, idx|
          lines << "#{idx + 1}. id: #{entry[:id] || entry['id']}"
          lines << "   title: #{entry[:title] || entry['title']}"
          lines << "   summary_excerpt_50_words: #{entry[:summary_excerpt_50_words] || entry['summary_excerpt_50_words']}"
        end
      end

      if in_thread_reply_context?(context)
        lines << "Treat this memory index as optional background only; prioritize current conversation thread context first."
      else
        lines << "Use memory tools only if required details are missing from the current conversation context or explicitly requested by the user."
      end
      lines.join("\n")
    end

    def build_council_context_message(context)
      council = context[:council]
      participants = context[:participants]
      conversation = context[:conversation]

      has_council = council.respond_to?(:name) || council.respond_to?(:description)
      has_participants = participants.respond_to?(:any?) && participants.any?
      has_conversation = conversation.respond_to?(:id) && conversation.id.present?
      return nil unless has_council || has_participants || has_conversation

      lines = [ "You are a member of a council of advisors." ]

      if has_conversation
        lines << "Conversation ID: #{conversation.id}"
      end

      if has_council
        lines << "Council: #{council.name}" if council.respond_to?(:name) && council.name.present?

        council_purpose = if council.respond_to?(:description)
          council.description
        end
        lines << "Purpose: #{council_purpose.presence || "No council purpose provided."}"
      else
        lines << "Purpose: No council purpose provided."
      end

      if has_participants
        lines << "Advisors and roles:"
        participants.each_with_index do |participant, idx|
          participant_name = participant[:name] || participant["name"] || "Unknown participant"
          participant_role = participant[:role] || participant["role"] || "advisor"
          lines << "#{idx + 1}. #{participant_name} (#{participant_role})"
        end
      end

      # responder = context[:advisor]
      # if responder.respond_to?(:name)
      #   responder_role = if responder.respond_to?(:scribe?) && responder.scribe?
      #     "scribe"
      #   else
      #     "advisor"
      #   end
      #   lines << "Current responder: #{responder.name} (#{responder_role})"
      # end

      # roe_type = context[:roe_type]
      # roe_description = context[:roe_description]
      # if roe_type.present? || roe_description.present?
      #   lines << "Rules of engagement: #{[ roe_type, roe_description ].compact.join(" - ")}"
      # end

      lines.join("\n")
    end

    def build_tool_policy_context_message(context, messages)
      message = context[:message]
      parent_message = context[:parent_message] || message&.parent_message
      is_reply = parent_message.present?
      last_user_content = extract_last_user_content(messages)
      references_thread = references_in_thread_context?(last_user_content)
      rich_inline_context = rich_inline_context_provided?(last_user_content)

      lines = [ "Response policy (hard rules):" ]
      lines << "- Prioritize the provided current conversation messages as your primary source of truth."
      lines << "- Answer directly before considering tools."
      lines << "- Use tools only when information is genuinely missing from the current conversation context."

      if is_reply
        lines << "- This is a reply to an in-thread message: do not search memories or other conversations unless the user explicitly asks for lookup outside the current thread."
      else
        lines << "- Avoid searching memories or other conversations unless the user asks for it or current-thread context is insufficient."
      end

      if references_thread || rich_inline_context
        lines << "- The latest user message references or includes substantial in-thread context. For this turn, do not call tools; answer using the current conversation content only."
      end

      lines << "- Do not prefix your response with speaker labels such as '[speaker: ...]'; start directly with the answer content."
      lines << "- Use @user only when explicitly requesting a response from the user; otherwise use plain 'user' when referring to the user."
      lines << "- Do not call write/admin tools unless the user explicitly requests that action."
      lines.join("\n")
    end

    def in_thread_reply_context?(context)
      message = context[:message]
      parent_message = context[:parent_message] || message&.parent_message
      parent_message.present?
    end

    def extract_last_user_content(messages)
      msg = messages.reverse.find do |entry|
        role = entry[:role] || entry["role"]
        role.to_s == "user"
      end

      return "" unless msg

      (msg[:content] || msg["content"]).to_s
    end

    def references_in_thread_context?(content)
      return false if content.blank?

      content.match?(/\b(above|below|previous|earlier|following|message above|message below|summary above|summary below|this thread|current conversation|quoted below|pasted below)\b/i)
    end

    def rich_inline_context_provided?(content)
      return false if content.blank?

      long_form = content.length >= 500
      structured = content.match?(/\n\s*\#{1,6}\s+/) || content.match?(/\*\*.+\*\*/) || content.match?(/\[speaker:/i)

      long_form && structured
    end
  end
end


module RubyLLM
  module Providers
    class OpenAI
      module Tools
        module_function

        def parse_tool_call_arguments(tool_call)
          arguments = tool_call.dig("function", "arguments")

          if arguments.nil? || arguments.empty?
            {}
          else
            begin
              JSON.parse(arguments)
            rescue JSON::ParserError
              Rails.logger.debug "Failed to parse tool call arguments as JSON: #{arguments.inspect}"
              {}
            end
          end
        end
      end
    end
  end
end
