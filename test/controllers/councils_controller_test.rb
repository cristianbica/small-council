require "test_helper"

class CouncilsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    # Ensure account has a space for tests
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
  end

  test "should redirect to sign in when not authenticated" do
    get councils_url
    assert_redirected_to sign_in_url
  end

  test "should get index when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get councils_url
    assert_response :success
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get new_space_council_url(@space)
    assert_response :success
  end

  test "should create council when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_difference("Council.count") do
      post councils_url, params: { council: { name: "Test Council", description: "A test council" } }
    end
    council = Council.last
    assert_equal @space.id, council.space_id
    assert_redirected_to council_url(council)
  end

  test "should show council when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user, space: @space)
    get council_url(council)
    assert_response :success
  end

  test "should get edit for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user, space: @space)
    get edit_council_url(council)
    assert_response :success
  end

  test "should not get edit for non-creator" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    council = @account.councils.create!(name: "Test", user: other_user, space: @space)
    get edit_council_url(council)
    assert_redirected_to space_councils_path(@space)
  end

  test "should update council for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user, space: @space)
    patch council_url(council), params: { council: { name: "Updated Name" } }
    assert_redirected_to council_url(council)
    assert_equal "Updated Name", council.reload.name
  end

  test "should destroy council for creator" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user, space: @space)
    assert_difference("Council.count", -1) do
      delete council_url(council)
    end
    assert_redirected_to space_councils_path(@space)
  end

  test "should get index scoped to space" do
    sign_in_as(@user)
    set_tenant(@account)
    get space_councils_url(@space)
    assert_response :success
  end

  test "should create council in specific space" do
    sign_in_as(@user)
    set_tenant(@account)
    other_space = @account.spaces.create!(name: "Other Space")

    assert_difference("Council.count") do
      post space_councils_url(other_space), params: { council: { name: "Space Council", description: "In specific space" } }
    end

    council = Council.last
    assert_equal other_space.id, council.space_id
    assert_redirected_to council_url(council)
  end

  test "create renders new on validation failure" do
    sign_in_as(@user)
    set_tenant(@account)

    assert_no_difference("Council.count") do
      post councils_url, params: { council: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update renders edit on validation failure" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test", user: @user, space: @space)

    patch council_url(council), params: { council: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "should redirect when non-creator tries to access edit" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    council = @account.councils.create!(name: "Test", user: other_user, space: @space)

    get edit_council_url(council)
    assert_redirected_to space_councils_path(@space)
    assert_equal "Only the creator can modify this council.", flash[:alert]
  end

  test "should redirect when non-creator tries to update" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    council = @account.councils.create!(name: "Test", user: other_user, space: @space)

    patch council_url(council), params: { council: { name: "Updated" } }
    assert_redirected_to space_councils_path(@space)
    assert_equal "Test", council.reload.name
  end

  test "should redirect when non-creator tries to destroy" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    council = @account.councils.create!(name: "Test", user: other_user, space: @space)

    assert_no_difference("Council.count") do
      delete council_url(council)
    end
    assert_redirected_to space_councils_path(@space)
  end
end
