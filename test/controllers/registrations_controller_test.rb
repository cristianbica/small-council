require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get sign_up_url
    assert_response :success
  end

  test "should sign up" do
    assert_difference([ "Account.count", "User.count" ]) do
      post sign_up_url, params: {
        account: {
          name: "Test Organization",
          slug: "test-org",
          users_attributes: [
            { email: "test@example.com", password: "password123", password_confirmation: "password123" }
          ]
        }
      }
    end

    assert_redirected_to root_url

    user = User.find_by(email: "test@example.com")
    assert user.admin?
  end

  test "failed sign up renders new" do
    assert_no_difference([ "Account.count", "User.count" ]) do
      post sign_up_url, params: {
        account: {
          name: "",
          slug: "",
          users_attributes: [
            { email: "", password: "", password_confirmation: "" }
          ]
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
