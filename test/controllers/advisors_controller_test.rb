require "test_helper"

class AdvisorsControllerTest < ActionDispatch::IntegrationTest
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
  end

  test "should redirect to sign in when not authenticated" do
    set_tenant(@account)
    get new_space_advisor_url(@space)
    assert_redirected_to sign_in_url
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get new_space_advisor_url(@space)
    assert_response :success
  end

  test "should create advisor when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_difference("Advisor.count") do
      post space_advisors_url(@space), params: {
        advisor: {
          name: "Test Advisor",
          system_prompt: "You are helpful",
          llm_model_id: @llm_model.id
        }
      }
    end
    assert_redirected_to space_advisors_path(@space)

    advisor = Advisor.last
    assert_equal @llm_model, advisor.llm_model
    assert_equal @space, advisor.space
  end

  test "should get edit" do
    sign_in_as(@user)
    set_tenant(@account)
    advisor = @account.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )
    get edit_space_advisor_url(@space, advisor)
    assert_response :success
  end

  test "should update advisor" do
    sign_in_as(@user)
    set_tenant(@account)
    advisor = @account.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )
    patch space_advisor_url(@space, advisor), params: {
      advisor: { name: "Updated Name" }
    }
    assert_redirected_to space_advisors_path(@space)

    advisor.reload
    assert_equal "updated-name", advisor.name
  end

  test "should destroy advisor" do
    sign_in_as(@user)
    set_tenant(@account)
    advisor = @account.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )
    assert_difference("Advisor.count", -1) do
      delete space_advisor_url(@space, advisor)
    end
    assert_redirected_to space_advisors_path(@space)
  end

  test "create renders new on validation failure" do
    sign_in_as(@user)
    set_tenant(@account)

    post space_advisors_url(@space), params: {
      advisor: { name: "", system_prompt: "" }
    }
    assert_response :unprocessable_entity
  end

  test "update renders edit on validation failure" do
    sign_in_as(@user)
    set_tenant(@account)
    advisor = @account.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    patch space_advisor_url(@space, advisor), params: {
      advisor: { name: "" }
    }
    assert_response :unprocessable_entity
  end

  test "should redirect when space not found" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_space_advisor_url(space_id: 99999)
    assert_redirected_to spaces_path
    assert_equal "Space not found.", flash[:alert]
  end

  test "should redirect when advisor not found in space" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create advisor in a different space
    other_space = @account.spaces.create!(name: "Other Space")
    advisor_in_other_space = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "Test",
      account: @account,
      llm_model: @llm_model,
      space: other_space
    )

    get edit_space_advisor_url(@space, advisor_in_other_space)
    assert_redirected_to space_advisors_path(@space)
    assert_equal "Advisor not found.", flash[:alert]
  end

  test "should get index" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create a few advisors in the space
    @account.advisors.create!(
      name: "Advisor One",
      system_prompt: "Test",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )
    @account.advisors.create!(
      name: "Advisor Two",
      system_prompt: "Test",
      account: @account,
      llm_model: @llm_model,
      space: @space
    )

    get space_advisors_url(@space)
    assert_response :success
  end
end
