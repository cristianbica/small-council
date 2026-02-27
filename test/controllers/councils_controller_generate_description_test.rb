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

  test "generate_description returns generated name and description for creator" do
    AI::ContentGenerator.any_instance.stubs(:generate_council_description).returns({
      name: "Engineering Leadership Council",
      description: "A strategic council focused on engineering leadership and technical decisions."
    })

    post generate_description_council_url(@council),
         params: { concept: "A council for engineering leadership and technical decisions" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Engineering Leadership Council", json_response["name"]
    assert_equal "A strategic council focused on engineering leadership and technical decisions.", json_response["description"]
  end

  test "generate_description on collection route works for new councils" do
    AI::ContentGenerator.any_instance.stubs(:generate_council_description).returns({
      name: "Product Strategy Council",
      description: "A council for product strategy discussions and roadmap planning."
    })

    post generate_description_councils_url,
         params: { concept: "A council for product strategy discussions" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Product Strategy Council", json_response["name"]
    assert_equal "A council for product strategy discussions and roadmap planning.", json_response["description"]
  end

  test "generate_description requires concept parameter" do
    post generate_description_council_url(@council),
         params: { concept: "" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Please describe the council's purpose", json_response["error"]
  end

  test "generate_description requires concept parameter for collection route" do
    post generate_description_councils_url,
         params: {},
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Please describe the council's purpose", json_response["error"]
  end

  test "generate_description returns error when no free model available" do
    @free_model.update!(free: false)

    post generate_description_council_url(@council),
         params: { concept: "Test Council for technical decisions" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match /No AI model available/, json_response["error"]
  end

  test "generate_description returns error on API failure" do
    AI::ContentGenerator.any_instance.stubs(:generate_council_description).raises(
      AI::ContentGenerator::GenerationError.new("AI API error")
    )

    post generate_description_council_url(@council),
         params: { concept: "Test Council for technical decisions" },
         as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match /AI API error/, json_response["error"]
  end

  test "non-creator cannot generate descriptions for existing council" do
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    sign_in_as(other_user)

    post generate_description_council_url(@council),
         params: { concept: "Test Council for technical decisions" },
         as: :json

    assert_response :forbidden
    json_response = JSON.parse(response.body)
    assert_equal "Only the creator can modify this council.", json_response["error"]
  end

  test "generate_description works with valid concept and free model" do
    expected_name = "Strategic Planning Council"
    expected_description = "A council dedicated to strategic decision-making and technical excellence."
    AI::ContentGenerator.any_instance.stubs(:generate_council_description).returns({
      name: expected_name,
      description: expected_description
    })

    post generate_description_council_url(@council),
         params: { concept: "A council for strategic planning and technical excellence" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal expected_name, json_response["name"]
    assert_equal expected_description, json_response["description"]
  end
end
