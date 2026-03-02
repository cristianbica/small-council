# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium,
            using: :headless_chrome,
            screen_size: [1400, 1400],
            options: {
              browser: ENV.key?("SELENIUM_URL") ? :remote : :chrome,
              url: ENV.fetch("SELENIUM_URL", nil)
            }.compact

  def sign_in_as(user, password: "password123")
    visit sign_in_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_on "Sign in"
  end
end
