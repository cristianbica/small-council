# frozen_string_literal: true

require "test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite,
            screen_size: [1280, 1500],
            options: {
              js_errors: true,
              url: ENV.fetch("CHROME_URL", nil),
              browser_options: {
                "no-sandbox": nil
              }
            }.compact
  setup do
    Capybara.disable_animation = true
    Capybara.default_max_wait_time = 5
  end

  def sign_in_as(user, password: "password123")
    visit sign_in_path
    find("input[name='email']").set(user.email)
    find("input[name='password']").set(password)
    click_button "Sign in"
  end
end
