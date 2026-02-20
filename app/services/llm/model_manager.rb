module LLM
  class ModelManager
    ModelInfo = Struct.new(:provider, :model_id, :name, :enabled, :llm_model, :capabilities, keyword_init: true)

    def self.available_models(account)
      models = []

      # Preload all LLMModels for the account to avoid N+1 queries
      llm_models_by_key = account.llm_models.index_by { |m| [ m.provider_id, m.identifier ] }

      account.providers.enabled.each do |provider|
        provider.api.list_models.each do |model_data|
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
      client = LLM::Client.new(provider: provider, model: llm_model)
      info = client.info

      if info
        llm_model.name = info.name
        llm_model.enabled = true
        llm_model.metadata = {
          capabilities: {
            chat: info.type == "chat",
            vision: info.supports_vision?,
            json_mode: info.structured_output?,
            functions: info.supports_functions?
          },
          pricing: {
            input_price_per_million: info.input_price_per_million,
            output_price_per_million: info.output_price_per_million
          },
          context_window: info.context_window,
          max_tokens: info.max_tokens
        }
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
