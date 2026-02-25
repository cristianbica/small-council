require "test_helper"
require "ostruct"

class ContentGeneratorTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:one)
    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @free_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4",
      free: true,
      enabled: true
    )
  end

  # Profile validation
  test "raises UnknownProfileError for unknown profile" do
    assert_raises(ContentGenerator::UnknownProfileError) do
      ContentGenerator.generate(profile: :unknown, context: "test", account: @account)
    end
  end

  test "accepts string profile names" do
    mock_result = OpenStruct.new(content: '{"name":"Test Advisor","short_description":"A test","system_prompt":"You are a test"}')
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: "advisor", context: "test advisor", account: @account)
    assert_equal "Test Advisor", result[:name]
  end

  # Context validation
  test "raises GenerationError for blank context" do
    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: "", account: @account)
    end
  end

  test "raises GenerationError for nil context" do
    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: nil, account: @account)
    end
  end

  # Model selection
  test "uses default model when available" do
    @account.update!(default_llm_model: @free_model)

    mock_result = OpenStruct.new(content: '{"name":"Test","short_description":"Test","system_prompt":"Test"}')
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    assert_equal "Test", result[:name]
  end

  test "falls back to free model when no default" do
    mock_result = OpenStruct.new(content: '{"name":"Test","short_description":"Test","system_prompt":"Test"}')
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    assert_equal "Test", result[:name]
  end

  test "raises NoModelError when no model available" do
    @free_model.update!(free: false)

    assert_raises(ContentGenerator::NoModelError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end

  # Advisor profile
  test "advisor profile returns all three fields" do
    mock_result = OpenStruct.new(
      content: '{"name":"Financial Advisor","short_description":"Expert in retirement planning","system_prompt":"You are a financial advisor specializing in retirement planning."}'
    )
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :advisor, context: "retirement planning expert", account: @account)

    assert_equal "Financial Advisor", result[:name]
    assert_equal "Expert in retirement planning", result[:short_description]
    assert result[:system_prompt].present?
  end

  test "advisor profile handles markdown code blocks" do
    mock_result = OpenStruct.new(
      content: '```json\n{"name":"Code Block Advisor","short_description":"Test","system_prompt":"Test"}\n```'
    )
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    assert_equal "Code Block Advisor", result[:name]
  end

  test "advisor profile raises error when fields missing" do
    mock_result = OpenStruct.new(content: '{"name":"Incomplete Advisor"}')
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end

  test "advisor profile raises error for invalid JSON" do
    mock_result = OpenStruct.new(content: "This is not JSON at all")
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end

  test "advisor profile handles text before JSON" do
    mock_result = OpenStruct.new(
      content: 'Here is the advisor profile:\n\n{"name":"Delayed JSON","short_description":"Test","system_prompt":"Test"}'
    )
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    assert_equal "Delayed JSON", result[:name]
  end

  # Council profile
  test "council profile returns name and description" do
    mock_result = OpenStruct.new(
      content: '{"name":"Engineering Leadership Council","description":"A council of experienced engineering leaders focused on architecture decisions."}'
    )
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :council, context: "A council for engineering leadership", account: @account)

    assert_equal "Engineering Leadership Council", result[:name]
    assert_equal "A council of experienced engineering leaders focused on architecture decisions.", result[:description]
  end

  test "council profile strips extra whitespace from both fields" do
    mock_result = OpenStruct.new(
      content: '{"name":"  Strategic Council  ","description":"  Council description with whitespace  "}'
    )
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :council, context: "Test", account: @account)
    assert_equal "Strategic Council", result[:name]
    assert_equal "Council description with whitespace", result[:description]
  end

  test "council profile raises error when fields missing" do
    mock_result = OpenStruct.new(content: '{"name":"Incomplete Council"}')
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :council, context: "test", account: @account)
    end
  end

  # Conversation profile
  test "conversation profile returns title and initial_message" do
    mock_result = OpenStruct.new(
      content: '{"title":"Deployment Pipeline","initial_message":"Let\'s discuss how to optimize our deployment process."}'
    )
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = ContentGenerator.generate(profile: :conversation, context: "deployment pipeline", account: @account)

    assert_equal "Deployment Pipeline", result[:title]
    assert result[:initial_message].present?
  end

  # Error handling
  test "raises GenerationError on API error" do
    LLM::Client.any_instance.stubs(:chat).raises(LLM::APIError.new("API Error"))

    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end

  test "raises GenerationError on empty response" do
    LLM::Client.any_instance.stubs(:chat).returns(nil)

    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end

  test "raises GenerationError on empty content" do
    mock_result = OpenStruct.new(content: nil)
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    assert_raises(ContentGenerator::GenerationError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end

  # Available profiles
  test "exposes available profiles" do
    assert ContentGenerator::PROFILES.key?(:advisor)
    assert ContentGenerator::PROFILES.key?(:council)
    assert ContentGenerator::PROFILES.key?(:conversation)
  end

  test "each profile has required configuration" do
    ContentGenerator::PROFILES.each do |name, config|
      assert config[:fields].is_a?(Array), "#{name} should have fields array"
      assert config[:system_prompt].is_a?(String), "#{name} should have system_prompt string"
      assert [ :json, :text ].include?(config[:output_format]), "#{name} should have valid output_format"
    end
  end

  # Integration with existing model selection
  test "only considers enabled models" do
    @free_model.update!(enabled: false)

    assert_raises(ContentGenerator::NoModelError) do
      ContentGenerator.generate(profile: :advisor, context: "test", account: @account)
    end
  end
end
