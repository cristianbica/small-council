class ProviderConnectionTester
  def self.test(provider_type, api_key, organization_id = nil)
    # Create temporary provider instance for testing
    temp_provider = Provider.new(
      provider_type: provider_type,
      credentials: { "api_key" => api_key, "organization_id" => organization_id }
    )

    result = AI::Client.test_connection(provider: temp_provider)

    if result[:success]
      # Also return available models
      models = AI::Client.list_models(provider: temp_provider)
      { success: true, models: models.map { |m| m[:id] } }
    else
      { success: false, error: result[:error] }
    end
  rescue => e
    Rails.logger.debug "[ProviderConnectionTester] Error testing provider connection: #{e.message}"
    Rails.logger.debug e.backtrace.join("\n")
    { success: false, error: e.message }
  end
end
