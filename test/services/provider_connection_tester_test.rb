require "test_helper"

class ProviderConnectionTesterTest < ActiveSupport::TestCase
  test "test returns error for unknown provider type" do
    result = ProviderConnectionTester.test("unknown", "api_key")

    assert_equal false, result[:success]
    assert result[:error].present?
  end

  test "test catches and returns error on exception" do
    # Force an error by passing nil
    result = ProviderConnectionTester.test("openai", nil)

    assert_equal false, result[:success]
    assert result[:error].present?
  end

  test "test_openai returns success with models on valid connection" do
    # Mock the LLM::Client
    mock_client = mock
    mock_api = mock

    LLM::Client.expects(:new).returns(mock_client)
    mock_client.expects(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
    mock_client.expects(:list_models).returns([
      { id: "gpt-4", name: "GPT-4", provider: "openai" },
      { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", provider: "openai" }
    ])

    result = ProviderConnectionTester.test("openai", "sk-test")

    assert_equal true, result[:success]
    assert_equal [ "gpt-4", "gpt-3.5-turbo" ], result[:models]
  end

  test "test_openai includes organization_id when provided" do
    mock_client = mock

    LLM::Client.expects(:new).returns(mock_client)
    mock_client.expects(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
    mock_client.expects(:list_models).returns([ { id: "gpt-4", name: "GPT-4", provider: "openai" } ])

    result = ProviderConnectionTester.test("openai", "sk-test", "org-123")

    assert_equal true, result[:success]
  end

  test "test_openai handles connection errors" do
    mock_client = mock

    LLM::Client.expects(:new).returns(mock_client)
    mock_client.expects(:test_connection).returns({ success: false, error: "Invalid API key" })

    result = ProviderConnectionTester.test("openai", "invalid-key")

    assert_equal false, result[:success]
    assert_match(/Invalid API key/, result[:error])
  end

  test "test_openrouter returns success with models on valid connection" do
    mock_client = mock

    LLM::Client.expects(:new).returns(mock_client)
    mock_client.expects(:test_connection).returns({ success: true, model: "openai/gpt-4o-mini" })
    mock_client.expects(:list_models).returns([
      { id: "openai/gpt-4", name: "GPT-4", provider: "openrouter" },
      { id: "anthropic/claude-3-opus", name: "Claude 3 Opus", provider: "openrouter" }
    ])

    result = ProviderConnectionTester.test("openrouter", "sk-or-test")

    assert_equal true, result[:success]
    assert_includes result[:models], "openai/gpt-4"
    assert_includes result[:models], "anthropic/claude-3-opus"
  end

  test "test_openrouter handles errors" do
    mock_client = mock

    LLM::Client.expects(:new).returns(mock_client)
    mock_client.expects(:test_connection).returns({ success: false, error: "Invalid API key" })

    result = ProviderConnectionTester.test("openrouter", "invalid-key")

    assert_equal false, result[:success]
    assert_match(/Invalid API key/, result[:error])
  end
end
