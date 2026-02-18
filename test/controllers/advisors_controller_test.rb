require "test_helper"

class AdvisorsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")

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
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    get new_council_advisor_url(council)
    assert_redirected_to sign_in_url
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    get new_council_advisor_url(council)
    assert_response :success
  end

  test "should create advisor when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    assert_difference("Advisor.count") do
      post council_advisors_url(council), params: {
        advisor: {
          name: "Test Advisor",
          system_prompt: "You are helpful",
          llm_model_id: @llm_model.id
        }
      }
    end
    assert_redirected_to council_url(council)

    advisor = Advisor.last
    assert_equal @llm_model, advisor.llm_model
  end

  test "should get edit for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = council.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      council: council,
      llm_model: @llm_model
    )
    get edit_council_advisor_url(council, advisor)
    assert_response :success
  end

  test "should update advisor for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = council.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      council: council,
      llm_model: @llm_model
    )
    patch council_advisor_url(council, advisor), params: {
      advisor: { name: "Updated Name" }
    }
    assert_redirected_to council_url(council)

    advisor.reload
    assert_equal "Updated Name", advisor.name
  end

  test "should destroy advisor for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = council.advisors.create!(
      name: "Test",
      system_prompt: "Test prompt",
      account: @account,
      council: council,
      llm_model: @llm_model
    )
    assert_difference("Advisor.count", -1) do
      delete council_advisor_url(council, advisor)
    end
    assert_redirected_to council_url(council)
  end
end
