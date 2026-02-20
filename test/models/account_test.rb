require "test_helper"

class AccountTest < ActiveSupport::TestCase
  def setup
    # Create provider and model that can be reused in tests
    @provider_attributes = {
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    }
  end

  test "valid with name and slug" do
    account = Account.new(name: "Test Account", slug: "new-test-account")
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

  test "has many providers" do
    account = Account.new
    assert_respond_to account, :providers
  end

  test "has many llm_models" do
    account = Account.new
    assert_respond_to account, :llm_models
  end

  test "dependent destroy removes associated users" do
    account = Account.create!(name: "Test", slug: "test-destroy-users")
    account.users.create!(email: "test@example.com", password: "password123")
    assert_difference("User.count", -1) do
      account.destroy
    end
  end

  test "dependent destroy removes associated advisors" do
    account = Account.create!(name: "Test", slug: "test-destroy-advisors")
    provider = account.providers.create!(@provider_attributes)
    llm_model = provider.llm_models.create!(account: account, name: "GPT-4", identifier: "gpt-4")
    account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: llm_model
    )
    assert_difference("Advisor.count", -1) do
      account.destroy
    end
  end

  test "dependent destroy removes associated councils" do
    account = Account.create!(name: "Test", slug: "test-destroy-councils")
    user = account.users.create!(email: "test@example.com", password: "password123")
    space = account.spaces.create!(name: "Test Space")
    account.councils.create!(name: "Test Council", user: user, space: space)
    assert_difference("Council.count", -1) do
      account.destroy
    end
  end

  test "dependent destroy removes associated providers" do
    account = Account.create!(name: "Test", slug: "test-destroy-providers")
    account.providers.create!(@provider_attributes)
    assert_difference("Provider.count", -1) do
      account.destroy
    end
  end

  test "dependent destroy removes associated llm_models" do
    account = Account.create!(name: "Test", slug: "test-destroy-models")
    provider = account.providers.create!(@provider_attributes)
    provider.llm_models.create!(account: account, name: "GPT-4", identifier: "gpt-4")
    assert_difference("LLMModel.count", -1) do
      account.destroy
    end
  end

  # Scope tests
  test "with_global_advisors scope returns accounts with global advisors" do
    account = Account.create!(name: "Test", slug: "test-global-scope")
    provider = account.providers.create!(@provider_attributes)
    llm_model = provider.llm_models.create!(account: account, name: "GPT-4", identifier: "gpt-4")
    account.advisors.create!(
      name: "Global Advisor",
      system_prompt: "You are global",
      llm_model: llm_model,
      global: true
    )
    assert_includes Account.with_global_advisors, account
  end
end
