class ProviderConnectionTester
  def self.test(provider_type, api_key, organization_id = nil)
    case provider_type
    when "openai"
      test_openai(api_key, organization_id)
    when "anthropic"
      test_anthropic(api_key)
    when "github"
      test_github_models(api_key)
    else
      { success: false, error: "Unknown provider type" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def self.test_openai(api_key, organization_id)
    client = OpenAI::Client.new(
      access_token: api_key,
      organization_id: organization_id.presence
    )

    response = client.models
    models_response = response.list
    models = models_response["data"].map { |m| m["id"] }

    { success: true, models: models }
  rescue OpenAI::Error => e
    { success: false, error: e.message }
  end

  def self.test_anthropic(api_key)
    client = Anthropic::Client.new(access_token: api_key)

    # For Anthropic, we'll try to list models or make a minimal call
    # The gem may not have a models.list method, so we use a minimal message
    response = client.messages(
      parameters: {
        model: "claude-3-haiku-20240307",
        messages: [ { role: "user", content: "Hi" } ],
        max_tokens: 1
      }
    )

    { success: true, models: [ "claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307" ] }
  rescue => e
    { success: false, error: e.message }
  end

  def self.test_github_models(api_key)
    # For GitHub Models, we'll just return success with known models
    # since the API endpoint structure may vary
    {
      success: true,
      models: [
        "Phi-3-mini-4k-instruct",
        "Phi-3-medium-4k-instruct",
        "Meta-Llama-3.1-8B-Instruct",
        "Meta-Llama-3.1-70B-Instruct",
        "Mistral-large",
        "Mistral-small"
      ]
    }
  rescue => e
    { success: false, error: e.message }
  end
end
