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
end
