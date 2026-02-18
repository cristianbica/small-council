# frozen_string_literal: true

Rails.application.configure do
  # Allow requests from configured host
  config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?

  # Set host for mailer links
  config.action_mailer.default_url_options = { host: ENV["APP_HOST"] || "localhost", port: ENV["APP_HOST"].present? ? nil : 3000 }
end
