require "test_helper"
require "ostruct"

class DescriptionGeneratorTest < ActiveSupport::TestCase
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

  test "generate returns description from AI when free model available" do
    mock_result = { content: "A council focused on strategic engineering decisions and technical leadership." }
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = DescriptionGenerator.generate(
      name: "Engineering Leadership Council",
      account: @account
    )

    assert_equal "A council focused on strategic engineering decisions and technical leadership.", result
  end

  test "raises NoFreeModelError when no free model exists" do
    @free_model.update!(free: false)

    assert_raises(DescriptionGenerator::NoFreeModelError) do
      DescriptionGenerator.generate(
        name: "Test Council",
        account: @account
      )
    end
  end

  test "raises GenerationError when API call fails" do
    LLM::Client.any_instance.stubs(:chat).raises(LLM::APIError.new("API Error"))

    assert_raises(DescriptionGenerator::GenerationError) do
      DescriptionGenerator.generate(
        name: "Test Council",
        account: @account
      )
    end
  end

  test "raises GenerationError when result is nil" do
    LLM::Client.any_instance.stubs(:chat).returns(nil)

    assert_raises(DescriptionGenerator::GenerationError) do
      DescriptionGenerator.generate(
        name: "Test Council",
        account: @account
      )
    end
  end

  test "strips whitespace from generated description" do
    mock_result = { content: "  A compelling description with extra whitespace  " }
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    result = DescriptionGenerator.generate(
      name: "Test Council",
      account: @account
    )

    assert_equal "A compelling description with extra whitespace", result
  end

  test "builds user prompt with council name" do
    council_name = "Product Strategy Council"
    expected_prompt = <<~PROMPT
      Create a compelling description for an AI advisor council named:

      "#{council_name}"

      The description should explain what this council helps users accomplish.
    PROMPT

    mock_result = { content: "Generated description" }
    LLM::Client.any_instance.stubs(:chat).with(
      [ { role: "user", content: expected_prompt } ],
      system_prompt: DescriptionGenerator::DESCRIPTION_GENERATOR_SYSTEM_PROMPT,
      temperature: 0.7,
      max_tokens: 500
    ).returns(mock_result)

    result = DescriptionGenerator.generate(name: council_name, account: @account)
    assert_equal "Generated description", result
  end
end
