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
end
