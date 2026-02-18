require "test_helper"

class SpacesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
  end

  test "should redirect to sign in when not authenticated" do
    get spaces_url
    assert_redirected_to sign_in_url
  end

  test "should get index when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get spaces_url
    assert_response :success
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get new_space_url
    assert_response :success
  end

  test "should create space" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_difference("Space.count") do
      post spaces_url, params: { space: { name: "Test Space", description: "A test space" } }
    end

    space = Space.last
    assert_redirected_to space_councils_path(space)
    assert_equal "Space created successfully.", flash[:notice]
    assert_equal space.id, session[:space_id]
  end

  test "should show space and switch to it" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")
    get space_url(space)
    assert_redirected_to space_councils_path(space)
    assert_equal space.id, session[:space_id]
  end

  test "should get edit" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")
    get edit_space_url(space)
    assert_response :success
  end

  test "should update space" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")
    patch space_url(space), params: { space: { name: "Updated Name" } }
    assert_redirected_to space_councils_path(space)
    assert_equal "Updated Name", space.reload.name
  end

  test "should not create space with invalid params" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_no_difference("Space.count") do
      post spaces_url, params: { space: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "should not access space from other account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create other account and space without tenant scoping (so space gets correct account_id)
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Account", slug: "other-space-test-#{Time.now.to_i}")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Space")
    end

    # Verify other_account is different from @account
    assert other_account.id != @account.id, "other_account.id (#{other_account.id}) should not equal @account.id (#{@account.id})"

    # Verify the space belongs to other_account
    assert_equal other_account.id, other_space.account_id

    # Verify other_space is not in @account's spaces
    assert_not @account.spaces.exists?(other_space.id)

    # Now test the controller - should return 404 (Rails catches RecordNotFound in production)
    get space_url(other_space)
    assert_response :not_found
  end
end
