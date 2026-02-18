require "test_helper"

class CouncilsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
  end

  test "should redirect to sign in when not authenticated" do
    get councils_url
    assert_redirected_to sign_in_url
  end

  test "should get index when authenticated" do
    sign_in_as(@user)
    get councils_url
    assert_response :success
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    get new_council_url
    assert_response :success
  end

  test "should create council when authenticated" do
    sign_in_as(@user)
    assert_difference("Council.count") do
      post councils_url, params: { council: { name: "Test Council", description: "A test council" } }
    end
    assert_redirected_to council_url(Council.last)
  end

  test "should show council when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user)
    get council_url(council)
    assert_response :success
  end

  test "should get edit for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user)
    get edit_council_url(council)
    assert_response :success
  end

  test "should not get edit for non-creator" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    council = @account.councils.create!(name: "Test", user: other_user)
    get edit_council_url(council)
    assert_redirected_to councils_url
  end

  test "should update council for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user)
    patch council_url(council), params: { council: { name: "Updated Name" } }
    assert_redirected_to council_url(council)
    assert_equal "Updated Name", council.reload.name
  end

  test "should destroy council for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user)
    assert_difference("Council.count", -1) do
      delete council_url(council)
    end
    assert_redirected_to councils_url
  end
end
