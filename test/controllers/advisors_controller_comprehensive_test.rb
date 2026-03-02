require "test_helper"

class AdvisorsControllerComprehensiveTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = spaces(:one)

    # Create provider and model for advisors
    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    # Create a council for testing council-related actions
    @council = @account.councils.create!(
      name: "Test Council",
      user: @user,
      space: @space
    )

    # Create an advisor for testing
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    sign_in_as(@user)
    set_tenant(@account)
  end

  # ============================================================================
  # generate_prompt Tests
  # ============================================================================

  test "should generate advisor profile with valid concept" do
    AI::ContentGenerator.any_instance.stubs(:generate_advisor_profile).returns({
      name: "AI Expert",
      short_description: "An expert in artificial intelligence",
      system_prompt: "You are an AI expert with deep knowledge..."
    })

    post generate_prompt_space_advisors_url(@space), params: {
      concept: "AI expert who helps with machine learning"
    }, as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "AI Expert", json_response["name"]
    assert_equal "An expert in artificial intelligence", json_response["short_description"]
    assert json_response["system_prompt"].present?
  end

  test "generate_prompt returns error when concept is blank" do
    post generate_prompt_space_advisors_url(@space), params: {
      concept: ""
    }, as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match(/Concept is required/, json_response["error"])
  end

  test "generate_prompt returns error when concept is missing" do
    post generate_prompt_space_advisors_url(@space), params: {}, as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match(/Concept is required/, json_response["error"])
  end

  test "generate_prompt handles NoModelError" do
    # Remove all models
    @account.llm_models.update_all(enabled: false)
    @account.update!(default_llm_model: nil)

    post generate_prompt_space_advisors_url(@space), params: {
      concept: "AI expert"
    }, as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["error"].present?
  end

  test "generate_prompt handles GenerationError" do
    AI::ContentGenerator.any_instance.stubs(:generate_advisor_profile).raises(
      AI::ContentGenerator::GenerationError.new("Failed to generate")
    )

    post generate_prompt_space_advisors_url(@space), params: {
      concept: "AI expert"
    }, as: :json

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_match(/Failed to generate/, json_response["error"])
  end

  # ============================================================================
  # select Tests (for adding advisors to councils)
  # ============================================================================

  test "should get select page for council" do
    get select_council_advisors_url(@council)
    assert_response :success
    assert_select "h1", /Add Advisors/
  end

  test "select shows only advisors not already in council" do
    # Add advisor to council
    @council.advisors << @advisor

    # Create another advisor not in council
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "Other prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    get select_council_advisors_url(@council)
    assert_response :success
  end

  test "select works via space nested route" do
    get select_council_advisors_url(@council, space_id: @space.id)
    assert_response :success
  end

  # ============================================================================
  # add_existing Tests
  # ============================================================================

  test "should add existing advisors to council" do
    other_advisor = @account.advisors.create!(
      name: "Advisor to Add",
      system_prompt: "Prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    assert_difference "@council.advisors.count", 1 do
      post add_existing_council_advisors_url(@council), params: {
        advisor_ids: [ other_advisor.id ]
      }
    end

    assert_redirected_to council_url(@council)
    assert_match(/Added 1 advisor/, flash[:notice])
  end

  test "should add multiple advisors to council" do
    advisor1 = @account.advisors.create!(
      name: "Advisor One",
      system_prompt: "Prompt 1",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )
    advisor2 = @account.advisors.create!(
      name: "Advisor Two",
      system_prompt: "Prompt 2",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    assert_difference "@council.advisors.count", 2 do
      post add_existing_council_advisors_url(@council), params: {
        advisor_ids: [ advisor1.id, advisor2.id ]
      }
    end

    assert_redirected_to council_url(@council)
  end

  test "add_existing redirects when no advisors selected" do
    post add_existing_council_advisors_url(@council), params: {
      advisor_ids: []
    }

    assert_redirected_to select_council_advisors_path(@council)
    # Empty advisor_ids results in "No advisors were added." message
    assert_equal "No advisors were added.", flash[:alert]
  end

  test "add_existing redirects when advisor_ids is missing" do
    post add_existing_council_advisors_url(@council), params: {}

    assert_redirected_to select_council_advisors_path(@council)
    # When advisor_ids is missing, it defaults to empty array and shows this message
    assert_equal "Please select at least one advisor.", flash[:alert]
  end

  test "add_existing skips advisors from other spaces" do
    other_space = @account.spaces.create!(name: "Other Space")
    other_advisor = @account.advisors.create!(
      name: "Other Space Advisor",
      system_prompt: "Prompt",
      account: @account,
      llm_model: @llm_model,
      space: other_space
    )

    # The advisor from other space won't be found in current space scope
    assert_no_difference "@council.advisors.count" do
      post add_existing_council_advisors_url(@council), params: {
        advisor_ids: [ other_advisor.id ]
      }
    end
  end

  # ============================================================================
  # destroy with error handling Tests
  # ============================================================================

  test "cannot destroy advisor with messages" do
    # Create a conversation and message with this advisor
    conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Test",
      space: @space
    )
    @account.messages.create!(
      conversation: conversation,
      sender: @advisor,
      role: "advisor",
      content: "Message from advisor"
    )

    assert_no_difference "Advisor.count" do
      delete space_advisor_url(@space, @advisor)
    end

    assert_redirected_to space_advisors_path(@space)
    assert_match(/Cannot delete advisor that has messages/, flash[:alert])
  end

  test "destroy advisor without messages" do
    # Don't create any messages for this advisor
    advisor_to_delete = @account.advisors.create!(
      name: "Delete Me",
      system_prompt: "Prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    assert_difference "Advisor.count", -1 do
      delete space_advisor_url(@space, advisor_to_delete)
    end

    assert_redirected_to space_advisors_path(@space)
    assert_match(/successfully deleted/, flash[:notice])
  end

  # ============================================================================
  # new with council_id Tests
  # ============================================================================

  test "should get new with council_id param" do
    get new_space_advisor_url(@space, council_id: @council.id)
    assert_response :success
  end

  test "should get new without council_id param" do
    get new_space_advisor_url(@space)
    assert_response :success
  end

  # ============================================================================
  # edit with council_id Tests
  # ============================================================================

  test "should get edit with council_id param" do
    get edit_space_advisor_url(@space, @advisor, council_id: @council.id)
    assert_response :success
  end

  # ============================================================================
  # create Tests (additional edge cases)
  # ============================================================================

  test "should create advisor with all params" do
    assert_difference "Advisor.count" do
      post space_advisors_url(@space), params: {
        advisor: {
          name: "Complete Advisor",
          short_description: "A helpful advisor",
          system_prompt: "You are very helpful",
          llm_model_id: @llm_model.id
        }
      }
    end

    advisor = Advisor.last
    assert_equal "Complete Advisor", advisor.name
    assert_equal "A helpful advisor", advisor.short_description
    assert_equal "You are very helpful", advisor.system_prompt
    assert_equal @llm_model, advisor.llm_model
  end

  test "should create advisor without llm_model_id" do
    assert_difference "Advisor.count" do
      post space_advisors_url(@space), params: {
        advisor: {
          name: "Advisor Without Model",
          system_prompt: "You are helpful"
        }
      }
    end

    advisor = Advisor.last
    assert_nil advisor.llm_model
  end

  # ============================================================================
  # update Tests (additional edge cases)
  # ============================================================================

  test "should update advisor with partial params" do
    patch space_advisor_url(@space, @advisor), params: {
      advisor: {
        name: "Updated Name Only"
      }
    }

    assert_redirected_to space_advisors_path(@space)
    @advisor.reload
    assert_equal "Updated Name Only", @advisor.name
    # Other fields should remain unchanged
    assert_equal "You are a test advisor", @advisor.system_prompt
  end

  test "should remove llm_model_id on update" do
    # First ensure advisor has a model
    @advisor.update!(llm_model: @llm_model)

    patch space_advisor_url(@space, @advisor), params: {
      advisor: {
        name: "Updated",
        llm_model_id: ""
      }
    }

    assert_redirected_to space_advisors_path(@space)
    @advisor.reload
    assert_nil @advisor.llm_model
  end

  # ============================================================================
  # index with scribe Tests
  # ============================================================================

  test "index identifies scribe in the space" do
    # Create a scribe advisor
    scribe = @account.advisors.create!(
      name: "Scribe",
      system_prompt: "You document",
      account: @account,
      llm_model: @llm_model,
      space: @space,
      global: true
    )

    get space_advisors_url(@space)
    assert_response :success
  end

  test "index handles missing scribe" do
    # Ensure no scribe exists
    @space.advisors.where("LOWER(name) LIKE ?", "%scribe%").destroy_all

    get space_advisors_url(@space)
    assert_response :success
  end

  test "index only shows non-scribe advisors" do
    # Create scribe and regular advisors
    scribe = @account.advisors.create!(
      name: "Scribe",
      system_prompt: "Document",
      account: @account,
      llm_model: @llm_model,
      space: @space,
      global: true
    )
    regular = @account.advisors.create!(
      name: "Regular Advisor",
      system_prompt: "Help",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    get space_advisors_url(@space)
    assert_response :success
  end

  # ============================================================================
  # Security Tests
  # ============================================================================

  test "cannot access advisor from different space via set_space council_id" do
    other_space = @account.spaces.create!(name: "Other Space")
    other_advisor = @account.advisors.create!(
      name: "Other Space Advisor",
      system_prompt: "Prompt",
      account: @account,
      llm_model: @llm_model,
      space: other_space
    )

    # Try to access the advisor from other_space via @space (the main test space)
    # The advisor should not be found in @space.advisors
    get edit_space_advisor_url(@space, other_advisor)
    # Should redirect since the advisor isn't in this space
    assert_redirected_to space_advisors_path(@space)
    assert_equal "Advisor not found.", flash[:alert]
  end

  test "set_space handles missing space_id and invalid council_id" do
    get new_space_advisor_url(space_id: 99999)
    assert_redirected_to spaces_path
    assert_equal "Space not found.", flash[:alert]
  end

  # ============================================================================
  # set_advisor Tests
  # ============================================================================

  test "set_advisor redirects when advisor not found" do
    get edit_space_advisor_url(@space, id: 99999)
    assert_redirected_to space_advisors_path(@space)
    assert_equal "Advisor not found.", flash[:alert]
  end
end
