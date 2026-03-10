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

  test "should get new" do
    get new_space_advisor_url(@space)
    assert_response :success
  end

  test "should get edit" do
    get edit_space_advisor_url(@space, @advisor)
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
    assert_equal "complete-advisor", advisor.name
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
    assert_equal "updated-name-only", @advisor.name
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

  test "cannot access advisor from different space" do
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

  test "set_space handles missing space_id" do
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
