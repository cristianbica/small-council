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

  test "allows authenticated users to access app and redirects to space councils" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.first

    get dashboard_url
    assert_redirected_to space_councils_path(space)

    follow_redirect!
    assert_response :success
  end

  test "shows dashboard when account has no spaces" do
    # Create fresh account without spaces
    fresh_account = Account.create!(name: "Fresh Account", slug: "fresh-test-#{Time.now.to_i}")
    fresh_user = fresh_account.users.create!(email: "fresh@example.com", password: "password123")

    # Verify no spaces exist
    assert_equal 0, fresh_account.spaces.count

    sign_in_as(fresh_user)
    set_tenant(fresh_account)

    # Dashboard shows successfully with no spaces
    get dashboard_url
    assert_response :success

    # Still no spaces (dashboard skips auto-creation)
    assert_equal 0, fresh_account.reload.spaces.count
  end

  test "auto-creates default space when accessing non-dashboard controller with no spaces" do
    # Create fresh account without spaces
    fresh_account = Account.create!(name: "Fresh Account 2", slug: "fresh-test-2-#{Time.now.to_i}")
    fresh_user = fresh_account.users.create!(email: "fresh2@example.com", password: "password123")

    assert_equal 0, fresh_account.spaces.count

    sign_in_as(fresh_user)
    set_tenant(fresh_account)

    # Accessing spaces index triggers auto-creation
    get spaces_url

    # Space was auto-created
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

    # Visit dashboard - should redirect to the session space councils
    get dashboard_url
    assert_redirected_to space_councils_path(other_space)

    follow_redirect!
    assert_response :success
  end

  test "set_current_space uses session space_id branch in non-dashboard controller" do
    sign_in_as(@user)
    set_tenant(@account)

    space = @account.spaces.first

    # Visit a space page to set session[:space_id]
    get space_url(space)
    assert_equal space.id, session[:space_id]

    # Now visit spaces index (uses set_current_space) — exercises session[:space_id] true branch
    get spaces_url
    assert_response :success
  end

  test "falls back to first space when session space_id is stale" do
    sign_in_as(@user)
    set_tenant(@account)

    space = @account.spaces.first
    get space_url(space)
    assert_equal space.id, session[:space_id]

    session[:space_id] = -1
    get spaces_url

    assert_response :success
  end

  test "supports page modal turbo frame header" do
    sign_in_as(@user)
    set_tenant(@account)

    get dashboard_url, headers: { "Turbo-Frame" => "page-modal" }

    assert_response :redirect
  end

  test "non page-modal turbo frame header follows normal variant" do
    sign_in_as(@user)
    set_tenant(@account)

    get dashboard_url, headers: { "Turbo-Frame" => "sidebar" }

    assert_response :redirect
  end

  test "unauthenticated request keeps tenant unset" do
    ActsAsTenant.current_tenant = @account

    get dashboard_url

    assert_redirected_to sign_in_url
    assert_nil Current.account
  end
end
