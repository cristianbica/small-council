require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "should redirect to sign in when not authenticated" do
    get dashboard_url
    assert_redirected_to sign_in_url
  end

  test "should get index when authenticated" do
    user = users(:one)
    sign_in_as(user)

    get dashboard_url
    assert_response :success
  end

  test "root path redirects to dashboard" do
    get root_url
    assert_redirected_to sign_in_url
  end
end
