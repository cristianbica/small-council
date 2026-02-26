require "test_helper"

class SpaceTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:one)
    set_tenant(@account)
  end

  test "should be valid with name and account" do
    space = @account.spaces.new(name: "Test Space")
    assert space.valid?
  end

  test "should require name" do
    space = @account.spaces.new(name: "")
    assert_not space.valid?
    assert_includes space.errors[:name], "can't be blank"
  end

  test "should require unique name per account" do
    @account.spaces.create!(name: "Duplicate")
    space = @account.spaces.new(name: "Duplicate")
    assert_not space.valid?
    assert_includes space.errors[:name], "has already been taken"
  end

  test "should allow same name in different accounts" do
    ActsAsTenant.without_tenant do
      account2 = Account.create!(name: "Other", slug: "other")
      @account.spaces.create!(name: "Shared Name")
      space2 = account2.spaces.new(name: "Shared Name")
      assert space2.valid?
    end
  end

  test "should require account" do
    ActsAsTenant.without_tenant do
      space = Space.new(name: "Test")
      assert_not space.valid?
      assert_includes space.errors[:account], "must exist"
    end
  end

  test "should have many councils" do
    space = @account.spaces.new(name: "Test")
    assert_respond_to space, :councils
  end

  test "should have many conversations through councils" do
    space = @account.spaces.new(name: "Test")
    assert_respond_to space, :conversations
  end

  test "should destroy dependent councils" do
    space = @account.spaces.create!(name: "Test Space")
    user = @account.users.first
    space.councils.create!(name: "Test Council", user: user, account: @account)

    assert_difference("Council.count", -1) do
      space.destroy
    end
  end

  test "acts_as_tenant scopes to account" do
    ActsAsTenant.without_tenant do
      account2 = Account.create!(name: "Other", slug: "other-tenant-test")
      account2.spaces.create!(name: "Other Space")

      @account.spaces.create!(name: "This Space")
    end

    set_tenant(@account)
    # Should only see spaces for this account (account:one has 1 from fixtures + 1 created above)
    assert Space.count >= 1
    assert Space.where(name: "This Space").exists?
    assert_not Space.where(name: "Other Space").exists?
  end
end
