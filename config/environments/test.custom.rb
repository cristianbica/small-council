# frozen_string_literal: true

Rails.application.configure do
  # Allow requests from configured host (for system tests)
  config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?

  # Set host for mailer links
  config.action_mailer.default_url_options = { host: ENV["APP_HOST"] || "localhost:3000" }

  config.hosts << /.*/

  # config.eager_load = true
end
