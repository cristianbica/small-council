class ProviderConnectionTester
  def self.test(provider_type, api_key, organization_id = nil)
    # Create temporary provider instance for testing
    temp_provider = Provider.new(
      provider_type: provider_type,
      credentials: { "api_key" => api_key, "organization_id" => organization_id }
    )

    result = temp_provider.api.test_connection

    if result[:success]
      # Also return available models
      models = temp_provider.api.list_models
      { success: true, models: models.map { |m| m[:id] } }
    else
      { success: false, error: result[:error] }
    end
  rescue => e
    { success: false, error: e.message }
  end
end
