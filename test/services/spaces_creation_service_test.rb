require "test_helper"

class Spaces::CreationServiceTest < ActiveSupport::TestCase
  def setup
    # Create a fresh account without any spaces (unlike the fixture account)
    @account = Account.create!(name: "Test Account", slug: "test-creation-service-#{Time.now.to_i}")
    set_tenant(@account)
  end

  test "creates default space with correct attributes" do
    assert_difference("Space.count") do
      Spaces::CreationService.create_default_for_account(@account)
    end

    space = Space.last
    assert_equal "General", space.name
    assert_equal "Default space for your councils", space.description
    assert_equal @account.id, space.account_id
  end

  test "raises error when creating duplicate default space" do
    Spaces::CreationService.create_default_for_account(@account)

    assert_raises(ActiveRecord::RecordInvalid) do
      Spaces::CreationService.create_default_for_account(@account)
    end
  end
end
