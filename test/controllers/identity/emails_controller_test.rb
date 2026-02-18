require "test_helper"

class Identity::EmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = sign_in_as(users(:one))
  end

  test "should get edit" do
    get edit_identity_email_url
    assert_response :success
  end

  test "should update email" do
    patch identity_email_url, params: { email: "new_email@example.com", password_challenge: "password123" }
    assert_redirected_to root_url
  end

  test "should not update email with wrong password challenge" do
    patch identity_email_url, params: { email: "new_email@example.com", password_challenge: "wrongpassword" }

    assert_response :unprocessable_entity
    assert_select "li", /Password challenge is invalid/
  end
end
