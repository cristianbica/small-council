require "test_helper"

class ProviderConnectionTesterTest < ActiveSupport::TestCase
  test "test returns error for unknown provider type" do
    result = ProviderConnectionTester.test("unknown", "api_key")

    assert_equal false, result[:success]
    assert_equal "Unknown provider type", result[:error]
  end

  test "test catches and returns error on exception" do
    # Force an error by passing nil
    result = ProviderConnectionTester.test("openai", nil)

    assert_equal false, result[:success]
    assert result[:error].present?
  end

  test "test_openai returns success with models on valid connection" do
    # Mock the OpenAI client
    mock_client = mock
    mock_models = mock
    mock_response = { "data" => [ { "id" => "gpt-4" }, { "id" => "gpt-3.5-turbo" } ] }

    OpenAI::Client.expects(:new)
      .with(access_token: "sk-test", organization_id: nil)
      .returns(mock_client)
    mock_client.expects(:models).returns(mock_models)
    mock_models.expects(:list).returns(mock_response)

    result = ProviderConnectionTester.test("openai", "sk-test")

    assert_equal true, result[:success]
    assert_equal [ "gpt-4", "gpt-3.5-turbo" ], result[:models]
  end

  test "test_openai includes organization_id when provided" do
    mock_client = mock
    mock_models = mock
    mock_response = { "data" => [ { "id" => "gpt-4" } ] }

    OpenAI::Client.expects(:new)
      .with(access_token: "sk-test", organization_id: "org-123")
      .returns(mock_client)
    mock_client.expects(:models).returns(mock_models)
    mock_models.expects(:list).returns(mock_response)

    result = ProviderConnectionTester.test("openai", "sk-test", "org-123")

    assert_equal true, result[:success]
  end

  test "test_openai handles OpenAI errors" do
    mock_client = mock
    mock_models = mock

    OpenAI::Client.expects(:new).returns(mock_client)
    mock_client.expects(:models).returns(mock_models)
    mock_models.expects(:list).raises(OpenAI::Error.new("Invalid API key"))

    result = ProviderConnectionTester.test("openai", "invalid-key")

    assert_equal false, result[:success]
    assert_match(/Invalid API key/, result[:error])
  end

  test "test_anthropic returns success with models on valid connection" do
    mock_client = mock

    Anthropic::Client.expects(:new)
      .with(access_token: "test-key")
      .returns(mock_client)
    mock_client.expects(:messages).returns({ "content" => [ { "text" => "Hi" } ] })

    result = ProviderConnectionTester.test("anthropic", "test-key")

    assert_equal true, result[:success]
    assert_includes result[:models], "claude-3-opus-20240229"
    assert_includes result[:models], "claude-3-sonnet-20240229"
    assert_includes result[:models], "claude-3-haiku-20240307"
  end

  test "test_anthropic handles errors" do
    mock_client = mock

    Anthropic::Client.expects(:new).returns(mock_client)
    mock_client.expects(:messages).raises(StandardError.new("Invalid API key"))

    result = ProviderConnectionTester.test("anthropic", "invalid-key")

    assert_equal false, result[:success]
    assert_match(/Invalid API key/, result[:error])
  end

  test "test_github_models returns success with static models list" do
    result = ProviderConnectionTester.test("github", "ghp-test")

    assert_equal true, result[:success]
    assert_includes result[:models], "Phi-3-mini-4k-instruct"
    assert_includes result[:models], "Meta-Llama-3.1-8B-Instruct"
    assert_includes result[:models], "Mistral-large"
  end
end
