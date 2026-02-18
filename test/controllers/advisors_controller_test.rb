require "test_helper"

class AdvisorsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
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
        advisor: { name: "Test Advisor", system_prompt: "You are helpful" }
      }
    end
    assert_redirected_to council_url(council)
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
      model_provider: "openai",
      model_id: "gpt-4"
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
      model_provider: "openai",
      model_id: "gpt-4"
    )
    patch council_advisor_url(council, advisor), params: {
      advisor: { name: "Updated Name" }
    }
    assert_redirected_to council_url(council)
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
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert_difference("Advisor.count", -1) do
      delete council_advisor_url(council, advisor)
    end
    assert_redirected_to council_url(council)
  end
end
