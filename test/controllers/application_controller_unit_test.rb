require "test_helper"

class ApplicationControllerUnitTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @user = users(:one)
    @controller = ApplicationController.new
    @request = ActionDispatch::TestRequest.create
    @controller.stubs(:request).returns(@request)
  end

  teardown do
    Current.reset
    ActsAsTenant.current_tenant = nil
  end

  test "set_page_modal_variant sets modal only for page-modal frame" do
    @request.headers["Turbo-Frame"] = "page-modal"

    @controller.send(:set_page_modal_variant)

    assert_equal [ :modal ], @request.variant
  end

  test "set_page_modal_variant leaves variant unchanged for other frames" do
    @request.headers["Turbo-Frame"] = "sidebar"

    @controller.send(:set_page_modal_variant)

    assert_equal [], @request.variant
  end

  test "set_current_space returns early when account is missing" do
    Current.account = nil
    Current.space = nil
    @controller.stubs(:session).returns({})

    @controller.send(:set_current_space)

    assert_nil Current.space
  end

  test "set_current_space uses session space id when present" do
    Current.account = @account
    selected_space = @account.spaces.create!(name: "Session Space")
    @controller.stubs(:session).returns({ space_id: selected_space.id })

    @controller.send(:set_current_space)

    assert_equal selected_space, Current.space
  end

  test "set_current_space creates default space when none exists" do
    fresh_account = Account.create!(name: "No Space Account", slug: "no-space-#{SecureRandom.hex(4)}")
    fresh_user = fresh_account.users.create!(email: "nospace-#{SecureRandom.hex(4)}@example.com", password: "password123")

    session = Session.create!(user: fresh_user, ip_address: "127.0.0.1", user_agent: "RSpec")
    Current.session = session
    Current.account = fresh_account
    @controller.stubs(:session).returns({})

    assert_equal 0, fresh_account.spaces.count

    @controller.send(:set_current_space)

    assert_equal "General", Current.space.name
    assert_equal 1, fresh_account.reload.spaces.count
  end
end
