# frozen_string_literal: true

module AI
  # Entry point for provider/model operations and class-based chat sessions.
  # Runtime chat execution is handled by AI::Client::Chat instances.
  class Client
    class Error < StandardError; end
    class RateLimitError < Error; end
    class APIError < Error; end


    def self.chat(model:)
      Chat.new(provider: build_provider(model), model: model)
    end

    def self.build_provider(model)
      RubyLLM.context do |config|
        configure_provider(config, model.provider)
      end
    end

    def self.model_info(model:)
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
          configure_provider(config, provider)
        end
        model_id = test_model_id || find_test_model_id(provider)

        chat = RubyLLM.chat(model: model_id)
        response = chat.ask("Test connection")

        { success: true, model: response.model }
      rescue => e
        Rails.logger.debug "[AI::Client] Error testing provider connection: #{e.message}"
        Rails.logger.debug e.backtrace.join("\n")
        { success: false, error: e.message }
      end

      private

      def find_test_model_id(provider)
        # Find first available model for this provider
        models = RubyLLM.models.by_provider(provider.provider_type.to_sym)
        model_list = models.respond_to?(:all) ? models.all : Array(models)

        free_model = model_list.find { |model| model.respond_to?(:free?) && model.free? }
        (free_model || model_list.first)&.id || default_test_model_id(provider.provider_type)
      end

      def default_test_model_id(provider_type)
        case provider_type
        when "anthropic"
          "claude-3-5-haiku-latest"
        else
          "gpt-3.5-turbo"
        end
      end

      def configure_provider(config, provider)
        case provider.provider_type
        when "openai"
          config.openai_api_key = provider.api_key
          config.openai_organization_id = provider.organization_id if provider.organization_id.present?
        when "openrouter"
          config.openrouter_api_key = provider.api_key
        when "anthropic"
          config.anthropic_api_key = provider.api_key
        else
          raise APIError, "Unsupported provider type: #{provider.provider_type}"
        end
      end
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
