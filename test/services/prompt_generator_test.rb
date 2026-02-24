require "test_helper"
require "ostruct"

class PromptGeneratorTest < ActiveSupport::TestCase
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

  test "generate returns prompt from AI when free model available" do
    # Mock the LLM API call
    mock_result = OpenStruct.new(content: "You are a helpful strategic advisor...")

    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = PromptGenerator.generate(
      description: "A strategic business advisor",
      account: @account
    )

    assert_equal "You are a helpful strategic advisor...", result
  end

  test "raises NoFreeModelError when no free model exists" do
    @free_model.update!(free: false)

    assert_raises(PromptGenerator::NoFreeModelError) do
      PromptGenerator.generate(
        description: "A strategic business advisor",
        account: @account
      )
    end
  end

  test "raises GenerationError when API call fails" do
    LLM::Client.any_instance.stubs(:chat).raises(LLM::APIError.new("API Error"))

    assert_raises(PromptGenerator::GenerationError) do
      PromptGenerator.generate(
        description: "A strategic business advisor",
        account: @account
      )
    end
  end

  test "raises GenerationError when result is nil" do
    LLM::Client.any_instance.stubs(:chat).returns(nil)

    assert_raises(PromptGenerator::GenerationError) do
      PromptGenerator.generate(
        description: "A strategic business advisor",
        account: @account
      )
    end
  end

  test "finds first enabled free model" do
    # Create another free model
    @provider.llm_models.create!(
      account: @account,
      name: "GPT-3.5",
      identifier: "gpt-3.5-turbo",
      free: true,
      enabled: true
    )

    mock_result = OpenStruct.new(content: "Generated prompt")
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    # Should use the first free model (GPT-4)
    result = PromptGenerator.generate(description: "Test", account: @account)
    assert_equal "Generated prompt", result
  end

  test "only considers enabled models" do
    @free_model.update!(enabled: false)

    assert_raises(PromptGenerator::NoFreeModelError) do
      PromptGenerator.generate(description: "Test", account: @account)
    end
  end

  test "builds user prompt with description" do
    description = "A financial advisor"
    expected_prompt = <<~PROMPT
      Create a system prompt for an AI advisor with the following description:

      "#{description}"

      The advisor should be helpful, professional, and focused on their area of expertise.
    PROMPT

    mock_client = mock("client")
    mock_result = OpenStruct.new(content: "Generated")

    # Verify the prompt is built correctly
    LLM::Client.expects(:new).returns(mock_client)
    mock_client.expects(:chat).with(
      [ { role: "user", content: expected_prompt } ],
      system_prompt: PromptGenerator::PROMPT_GENERATOR_SYSTEM_PROMPT,
      temperature: 0.7,
      max_tokens: 1500
    ).returns(mock_result)

    result = PromptGenerator.generate(description: description, account: @account)
    assert_equal "Generated", result
  end
end
