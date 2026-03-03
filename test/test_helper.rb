require "simplecov"
SimpleCov.start "rails" do
  # Filters
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"

  # Groups for organization
  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Helpers", "app/helpers"
  add_group "Views", "app/views"

  enable_coverage :branch
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

if ENV["CI"] || ENV["CHROME_URL"]
  net = Socket.ip_address_list.detect(&:ipv4_private?)
  ip = net.nil? ? "127.0.0.1" : net.ip_address
  Capybara.server_host = ip
  Capybara.always_include_port = true
end
Capybara.server = :puma, { Silent: true }
Capybara.reuse_server = false

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)

  parallelize_setup do |worker|
    SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
  end

  parallelize_teardown do |worker|
    SimpleCov.result
  end

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...

  # Helper to set tenant in model tests
  def set_tenant(account)
    ActsAsTenant.current_tenant = account
  end

  # Reset tenant after each test
  teardown do
    ActsAsTenant.current_tenant = nil
  end
end

class ActionDispatch::IntegrationTest
  setup do
    host! ENV["APP_HOST"] if ENV["APP_HOST"].present?
  end

  def sign_in_as(user, password: "password123")
    post sign_in_url, params: { email: user.email, password: password }
    assert_response :redirect
    user
  end

  def sign_out
    delete session_url(Current.session)
  end
end

class ActionController::TestCase
  # Ensure tenant is reset between controller tests
  teardown do
    ActsAsTenant.current_tenant = nil
  end
end
