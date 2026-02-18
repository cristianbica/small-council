require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = sign_in_as(users(:one))
  end

  test "should get edit" do
    get edit_password_url
    assert_response :success
  end

  test "should update password" do
    patch password_url, params: { password_challenge: "password123", password: "newpassword123", password_confirmation: "newpassword123" }
    assert_redirected_to root_url
  end

  test "should not update password with wrong password challenge" do
    patch password_url, params: { password_challenge: "wrongpassword", password: "newpassword123", password_confirmation: "newpassword123" }

    assert_response :unprocessable_entity
    assert_select "li", /Password challenge is invalid/
  end
end
