module LLM
  class Context
    def self.for_tenant(account)
      providers = account.providers.enabled

      RubyLLM.context do |config|
        providers.each do |provider|
          case provider.provider_type
          when "openai"
            config.openai_api_key = provider.api_key
            config.openai_organization_id = provider.organization_id
          when "openrouter"
            config.openrouter_api_key = provider.api_key
          end
        end
      end
    end
  end
end
