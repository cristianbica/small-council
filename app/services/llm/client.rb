module LLM
  class Client
    class MissingModelError < StandardError; end

    attr_reader :provider, :model

    def initialize(provider:, model: nil)
      @provider = provider
      @model = model
    end

    # Provider-level: List available models
    def list_models
      models = RubyLLM.models.by_provider(provider_type_slug)
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

    # Provider-level: Test connection with minimal API call
    def test_connection
      chat = build_context.chat(model: test_model_id)
      response = chat.ask("Test connection")

      { success: true, model: response.model }
    rescue => e
      { success: false, error: e.message }
    end

    # Model-level: Get model info from registry (fails if no model)
    def info
      raise MissingModelError, "Client initialized without a model" unless @model

      RubyLLM.models.find(api_identifier)
    rescue StandardError
      nil
    end

    # Model-level: Check capability support (fails if no model)
    def supports?(capability)
      raise MissingModelError, "Client initialized without a model" unless @model

      model_info = info
      return false unless model_info

      case capability
      when :vision then model_info.supports_vision?
      when :json_mode then model_info.structured_output?
      when :functions then model_info.supports_functions?
      else false
      end
    end

    # Model-level: Execute chat completion (fails if no model)
    def chat(messages, system_prompt: nil, temperature: 0.7, max_tokens: 1000)
      raise MissingModelError, "Client initialized without a model" unless @model

      context = build_context
      chat = context.chat(model: api_identifier)

      chat.with_system_message(system_prompt) if system_prompt

      messages.each do |msg|
        chat.add_message(role: msg[:role], content: msg[:content])
      end

      response = chat.complete

      {
        content: response.content,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        total_tokens: response.total_tokens,
        model: response.model,
        provider: @provider.provider_type
      }
    rescue => e
      raise LLM::APIError, "Chat completion failed: #{e.message}"
    end

    private

    def build_context
      RubyLLM.context do |config|
        case @provider.provider_type
        when "openai"
          config.openai_api_key = @provider.api_key
          config.openai_organization_id = @provider.organization_id
        when "openrouter"
          config.openrouter_api_key = @provider.api_key
        end
      end
    end

    def provider_type_slug
      case @provider.provider_type
      when "openai" then :openai
      when "openrouter" then :openrouter
      else @provider.provider_type.to_sym
      end
    end

    def test_model_id
      case @provider.provider_type
      when "openai" then "gpt-4o-mini"
      when "openrouter" then "openai/gpt-4o-mini"
      else "gpt-4o-mini"
      end
    end

    def api_identifier
      @model.identifier
    end
  end
end
