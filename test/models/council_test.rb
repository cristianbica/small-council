require "test_helper"

class CouncilTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-councils")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
  end

  # Validation tests
  test "valid with name, account, and user" do
    council = @account.councils.new(name: "Test Council", user: @user)
    assert council.valid?
  end

  test "invalid without name" do
    council = @account.councils.new(user: @user)
    assert_not council.valid?
    assert_includes council.errors[:name], "can't be blank"
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      council = Council.new(name: "Orphan Council", user: @user)
      assert_not council.valid?
      assert_includes council.errors[:account], "can't be blank"
    end
  end

  test "invalid without user" do
    council = @account.councils.new(name: "No User Council")
    assert_not council.valid?
    assert_includes council.errors[:user], "can't be blank"
  end

  # Association tests
  test "belongs to account" do
    council = Council.new
    assert_respond_to council, :account
  end

  test "belongs to user" do
    council = Council.new
    assert_respond_to council, :user
  end

  test "has many council_advisors" do
    council = Council.new
    assert_respond_to council, :council_advisors
  end

  test "has many advisors through council_advisors" do
    council = Council.new
    assert_respond_to council, :advisors
  end

  test "has many conversations" do
    council = Council.new
    assert_respond_to council, :conversations
  end

  test "dependent destroy removes associated council_advisors" do
    council = @account.councils.create!(name: "Test Council", user: @user)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    council.council_advisors.create!(advisor: advisor, position: 0)
    assert_difference("CouncilAdvisor.count", -1) do
      council.destroy
    end
  end

  test "dependent destroy removes associated conversations" do
    council = @account.councils.create!(name: "Test Council", user: @user)
    council.conversations.create!(user: @user, account: @account, title: "Test Conversation")
    assert_difference("Conversation.count", -1) do
      council.destroy
    end
  end

  test "advisors through association works" do
    council = @account.councils.create!(name: "Test Council", user: @user)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    council.council_advisors.create!(advisor: advisor, position: 0)
    assert_includes council.advisors, advisor
  end

  # Enum tests
  test "defaults to private visibility" do
    council = @account.councils.create!(name: "Test Council", user: @user)
    assert_equal "private_visibility", council.visibility
    assert council.visibility_private_visibility?
  end

  test "can be set to shared visibility" do
    council = @account.councils.create!(name: "Shared Council", user: @user, visibility: "shared")
    assert_equal "shared", council.visibility
    assert council.visibility_shared?
  end

  test "visibility enum with prefix works correctly" do
    council = @account.councils.create!(name: "Test Council", user: @user)
    assert council.visibility_private_visibility?
    assert_not council.visibility_shared?

    council.visibility_shared!
    assert council.visibility_shared?
    assert_not council.visibility_private_visibility?
  end

  test "invalid visibility raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.councils.create!(name: "Invalid Council", user: @user, visibility: "public")
    end
  end

  test "valid visibility values are private and shared" do
    assert_equal({ "private_visibility" => "private", "shared" => "shared" }, Council.visibilities)
  end
end
