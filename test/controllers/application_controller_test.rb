require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
  end

  test "redirects unauthenticated users to sign in" do
    get dashboard_url
    assert_redirected_to sign_in_url
  end

  test "allows authenticated users to access dashboard" do
    sign_in_as(@user)
    set_tenant(@account)
    get dashboard_url
    assert_response :success
  end

  test "auto-creates default space when account has no spaces" do
    # Create fresh account without spaces
    fresh_account = Account.create!(name: "Fresh Account", slug: "fresh-test-#{Time.now.to_i}")
    fresh_user = fresh_account.users.create!(email: "fresh@example.com", password: "password123")

    # Verify no spaces exist
    assert_equal 0, fresh_account.spaces.count

    sign_in_as(fresh_user)
    set_tenant(fresh_account)

    # First request should auto-create default space
    get dashboard_url
    assert_response :success

    # Verify space was created
    assert_equal 1, fresh_account.reload.spaces.count
    assert_equal "General", fresh_account.spaces.first.name
  end

  test "uses session space_id when available" do
    other_space = @account.spaces.create!(name: "Other Space")
    council = @account.councils.create!(name: "Test Council", user: @user, space: other_space)

    sign_in_as(@user)
    set_tenant(@account)

    # First visit space show to set the space in session
    get space_url(other_space)
    assert_redirected_to space_councils_path(other_space)

    # Now verify the session has the space_id
    assert_equal other_space.id, session[:space_id]

    # Visit dashboard - should work with the session space
    follow_redirect!
    assert_response :success
  end
end
