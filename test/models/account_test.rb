require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "valid with name and slug" do
    account = Account.new(name: "Test Account", slug: "test-account")
    assert account.valid?
  end

  test "invalid without name" do
    account = Account.new(slug: "test-account")
    assert_not account.valid?
    assert_includes account.errors[:name], "can't be blank"
  end

  test "invalid without slug" do
    account = Account.new(name: "Test Account")
    assert_not account.valid?
    assert_includes account.errors[:slug], "can't be blank"
  end

  test "invalid with duplicate slug" do
    Account.create!(name: "First Account", slug: "unique-slug")
    account = Account.new(name: "Second Account", slug: "unique-slug")
    assert_not account.valid?
    assert_includes account.errors[:slug], "has already been taken"
  end

  # Association tests
  test "has many users" do
    account = Account.new
    assert_respond_to account, :users
  end

  test "has many advisors" do
    account = Account.new
    assert_respond_to account, :advisors
  end

  test "has many councils" do
    account = Account.new
    assert_respond_to account, :councils
  end

  test "has many conversations" do
    account = Account.new
    assert_respond_to account, :conversations
  end

  test "has many messages" do
    account = Account.new
    assert_respond_to account, :messages
  end

  test "has many usage records" do
    account = Account.new
    assert_respond_to account, :usage_records
  end

  test "dependent destroy removes associated users" do
    account = Account.create!(name: "Test", slug: "test-destroy-users")
    account.users.create!(email: "test@example.com")
    assert_difference("User.count", -1) do
      account.destroy
    end
  end

  test "dependent destroy removes associated advisors" do
    account = Account.create!(name: "Test", slug: "test-destroy-advisors")
    account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert_difference("Advisor.count", -1) do
      account.destroy
    end
  end

  test "dependent destroy removes associated councils" do
    account = Account.create!(name: "Test", slug: "test-destroy-councils")
    user = account.users.create!(email: "test@example.com")
    account.councils.create!(name: "Test Council", user: user)
    assert_difference("Council.count", -1) do
      account.destroy
    end
  end

  # Scope tests
  test "with_global_advisors scope returns accounts with global advisors" do
    account = Account.create!(name: "Test", slug: "test-global-scope")
    account.advisors.create!(
      name: "Global Advisor",
      system_prompt: "You are global",
      model_provider: "openai",
      model_id: "gpt-4",
      global: true
    )
    assert_includes Account.with_global_advisors, account
  end
end
