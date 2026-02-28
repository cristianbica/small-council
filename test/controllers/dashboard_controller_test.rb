require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "should redirect to sign in when not authenticated" do
    get dashboard_url
    assert_redirected_to sign_in_url
  end

  test "should redirect to first space councils when authenticated with spaces" do
    user = users(:one)
    sign_in_as(user)
    account = accounts(:one)
    space = account.spaces.first

    get dashboard_url
    assert_redirected_to space_councils_path(space)
  end

  test "should show dashboard when authenticated but no spaces" do
    # Create a fresh account without spaces
    fresh_account = Account.create!(name: "No Spaces Account", slug: "no-spaces-#{Time.now.to_i}")
    fresh_user = fresh_account.users.create!(email: "nospaces@example.com", password: "password123")
    sign_in_as(fresh_user)
    set_tenant(fresh_account)

    get dashboard_url
    assert_response :success
  end

  test "root path redirects to sign in when not authenticated" do
    get root_url
    assert_redirected_to sign_in_url
  end

  test "should use session space_id to redirect when authenticated" do
    user = users(:one)
    sign_in_as(user)
    account = accounts(:one)
    space = account.spaces.first

    # Visit the space page first so session[:space_id] is set
    get space_url(space)
    assert_equal space.id, session[:space_id]

    # Now dashboard should pick up session[:space_id] branch
    get dashboard_url
    assert_redirected_to space_councils_path(space)
  end
end
