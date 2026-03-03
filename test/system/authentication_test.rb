require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "user can sign up" do
    visit sign_up_path

    find("input[name='account[name]']").set("Test Co")
    find("input[name='account[slug]']").set("test-co")
    find("input[name='account[users_attributes][0][email]']").set("user@example.com")
    find("input[name='account[users_attributes][0][password]']").set("password123")
    find("input[name='account[users_attributes][0][password_confirmation]']").set("password123")

    click_on "Create Account"

    assert_text "Welcome to Small Council!"
    assert_current_path %r{/spaces/\d+/councils}
  end

  test "user can sign in" do
    account = Account.create!(name: "Test Account", slug: "test-signin")
    user = account.users.create!(email: "test@example.com", password: "password123", role: :member)

    visit sign_in_path

    find("input[name='email']").set(user.email)
    find("input[name='password']").set("password123")
    click_button "Sign in"

    assert_text "Signed in successfully"
  end

  test "user can sign out" do
    account = Account.create!(name: "Test Account", slug: "test-signout")
    user = account.users.create!(email: "test@example.com", password: "password123", role: :member)

    visit sign_in_path
    find("input[name='email']").set(user.email)
    find("input[name='password']").set("password123")
    click_button "Sign in"

    visit sessions_path
    click_button "Log out", match: :first

    assert_current_path sign_in_path
  end

  test "protected routes redirect to sign in when not authenticated" do
    visit dashboard_path
    assert_current_path sign_in_path
  end
end
