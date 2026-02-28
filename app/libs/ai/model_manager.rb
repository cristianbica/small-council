# frozen_string_literal: true

module AI
  # Model management for LLM operations
  # Manages listing, enabling, and disabling LLM models
  class ModelManager
    ModelInfo = Struct.new(:provider, :model_id, :name, :enabled, :llm_model, :capabilities, keyword_init: true)

    def self.available_models(account)
      models = []

      # Preload all LLMModels for the account to avoid N+1 queries
      llm_models_by_key = account.llm_models.index_by { |m| [ m.provider_id, m.identifier ] }

      account.providers.enabled.each do |provider|
        AI::Client.list_models(provider: provider).each do |model_data|
          # Lookup from preloaded hash instead of querying database
          llm_model = llm_models_by_key[[ provider.id, model_data[:id] ]]

          models << ModelInfo.new(
            provider: provider,
            model_id: model_data[:id],
            name: model_data[:name],
            enabled: llm_model&.enabled || false,
            llm_model: llm_model,
            capabilities: model_data[:capabilities]
          )
        end
      end

      models
    end

    def self.enable_model(account, provider, model_id)
      # Use find_or_initialize_by to handle existing records
      llm_model = account.llm_models.find_or_initialize_by(
        provider: provider,
        identifier: model_id
      )

      # Update with metadata from API
      client = AI::Client.new(model: llm_model, system_prompt: "")
      info = client.info

      if info
        # Store full RubyLLM data
        full_metadata = info.as_json

        # Determine if model is free
        input_price = full_metadata.dig("pricing", "input").to_f
        output_price = full_metadata.dig("pricing", "output").to_f
        is_free = input_price == 0.0 && output_price == 0.0

        # Extract capabilities
        capabilities = {
          "chat" => full_metadata["type"] == "chat",
          "vision" => full_metadata["vision"] || false,
          "json_mode" => full_metadata["structured_output"] || false,
          "functions" => full_metadata["supports_functions"] || false,
          "streaming" => full_metadata["streaming"] || false
        }

        llm_model.name = info.name
        llm_model.enabled = true
        llm_model.metadata = full_metadata
        llm_model.free = is_free
        llm_model.context_window = full_metadata["context_window"]
        llm_model.capabilities = capabilities
      else
        # Fallback if ruby_llm doesn't have info
        llm_model.name ||= model_id.split("/").last
        llm_model.enabled = true
      end

      llm_model.save!
      llm_model
    end

    def self.disable_model(account, provider, model_id)
      llm_model = account.llm_models.find_by(
        provider: provider,
        identifier: model_id
      )

      return unless llm_model

      llm_model.update!(enabled: false)
      llm_model
    end
  end
end
