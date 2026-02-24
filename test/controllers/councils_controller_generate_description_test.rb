require "test_helper"
require "ostruct"

class CouncilsControllerGenerateDescriptionTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    # Create a free model for description generation
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

  test "generate_description returns generated description for creator" do
    mock_result = { content: "A strategic council focused on engineering leadership." }
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    post generate_description_council_url(@council),
         params: { name: "Engineering Leadership Council" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "A strategic council focused on engineering leadership.", json_response["description"]
  end

  test "generate_description on collection route works for new councils" do
    mock_result = { content: "A council for product strategy discussions." }
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    post generate_description_councils_url,
         params: { name: "Product Strategy Council" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "A council for product strategy discussions.", json_response["description"]
  end

  test "generate_description requires name parameter" do
    post generate_description_council_url(@council),
         params: { name: "" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Council name is required", json_response["error"]
  end

  test "generate_description requires name parameter for collection route" do
    post generate_description_councils_url,
         params: {},
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Council name is required", json_response["error"]
  end

  test "generate_description returns error when no free model available" do
    @free_model.update!(free: false)

    post generate_description_council_url(@council),
         params: { name: "Test Council" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match /No free AI model available/, json_response["error"]
  end

  test "generate_description returns error on API failure" do
    LLM::Client.any_instance.stubs(:chat).raises(LLM::APIError.new("API Error"))

    post generate_description_council_url(@council),
         params: { name: "Test Council" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match /AI API error/, json_response["error"]
  end

  test "non-creator cannot generate descriptions for existing council" do
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    sign_in_as(other_user)

    post generate_description_council_url(@council),
         params: { name: "Test Council" },
         as: :json

    assert_response :forbidden
    json_response = JSON.parse(response.body)
    assert_equal "Only the creator can modify this council.", json_response["error"]
  end

  test "generate_description works with valid name and free model" do
    expected_description = "A council dedicated to strategic decision-making and technical excellence."
    mock_result = { content: expected_description }
    LLM::Client.any_instance.stubs(:chat).returns(mock_result)

    post generate_description_council_url(@council),
         params: { name: "Strategic Planning Council" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal expected_description, json_response["description"]
  end
end
