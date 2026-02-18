require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "user can sign up" do
    visit sign_up_path

    fill_in "Company/Organization Name", with: "Test Co"
    fill_in "URL Slug", with: "test-co"
    fill_in "Email", with: "user@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"

    click_on "Create Account"

    assert_text "Welcome to Small Council!"
    assert_current_path root_path
  end

  test "user can sign in" do
    account = Account.create!(name: "Test Account", slug: "test-signin")
    user = account.users.create!(email: "test@example.com", password: "password123", role: :member)

    visit sign_in_path

    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_on "Sign in"

    assert_text "Signed in successfully"
  end

  test "user can sign out" do
    account = Account.create!(name: "Test Account", slug: "test-signout")
    user = account.users.create!(email: "test@example.com", password: "password123", role: :member)

    visit sign_in_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_on "Sign in"

    click_on "Sign out"

    assert_current_path sign_in_path
  end

  test "protected routes redirect to sign in when not authenticated" do
    visit dashboard_path
    assert_current_path sign_in_path
  end
end
