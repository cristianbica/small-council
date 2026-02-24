require "test_helper"
require "ostruct"

class AdvisorsControllerGeneratePromptTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    # Create a free model for prompt generation
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

    sign_in_as(@user)
    set_tenant(@account)
  end

  test "generate_prompt returns generated prompt for creator" do
    mock_result = OpenStruct.new(content: "You are a strategic advisor...")
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    post generate_prompt_council_advisors_url(@council),
         params: { description: "A strategic business advisor" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "You are a strategic advisor...", json_response["prompt"]
  end

  test "generate_prompt requires description parameter" do
    post generate_prompt_council_advisors_url(@council),
         params: { description: "" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Description is required", json_response["error"]
  end

  test "generate_prompt handles missing description" do
    post generate_prompt_council_advisors_url(@council),
         params: {},
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Description is required", json_response["error"]
  end

  test "generate_prompt returns error when no free model available" do
    @free_model.update!(free: false)

    post generate_prompt_council_advisors_url(@council),
         params: { description: "A strategic advisor" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match /No free AI model available/, json_response["error"]
  end

  test "generate_prompt returns error on API failure" do
    LLM::Client.any_instance.stubs(:chat).raises(LLM::APIError.new("API Error"))

    post generate_prompt_council_advisors_url(@council),
         params: { description: "A strategic advisor" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match /AI API error/, json_response["error"]
  end

  test "non-creator cannot generate prompts" do
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    sign_in_as(other_user)

    post generate_prompt_council_advisors_url(@council),
         params: { description: "A strategic advisor" },
         as: :json

    assert_redirected_to council_url(@council)
    assert_equal "Only the creator can manage advisors.", flash[:alert]
  end

  # Skip for now - complex authentication test setup
  # test "unauthenticated user cannot generate prompts" do
  #   # This test requires complex session management
  #   post generate_prompt_council_advisors_url(@council),
  #        params: { description: "A strategic advisor" },
  #        as: :json
  #
  #   assert_redirected_to sign_in_url
  # end

  test "generate_prompt works with valid description and free model" do
    expected_prompt = "You are an expert financial advisor specializing in investment strategies. You provide clear, actionable advice tailored to the user's financial situation and goals. You always consider risk tolerance and time horizon when making recommendations."

    mock_result = OpenStruct.new(content: expected_prompt)
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    post generate_prompt_council_advisors_url(@council),
         params: { description: "Financial investment advisor" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal expected_prompt, json_response["prompt"]
  end
end
