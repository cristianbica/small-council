require "test_helper"

class AdvisorTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-advisors")
    set_tenant(@account)

    # Create a provider and model for testing
    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )
  end

  # Validation tests
  test "valid with all required attributes" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a helpful test advisor",
      llm_model: @llm_model
    )
    assert advisor.valid?
  end

  test "invalid without name" do
    advisor = @account.advisors.new(
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:name], "can't be blank"
  end

  test "invalid without system_prompt for non-simple advisor" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      llm_model: @llm_model
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:system_prompt], "can't be blank"
  end

  test "invalid without llm_model for non-simple advisor" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:llm_model], "can't be blank"
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      advisor = Advisor.new(
        name: "Orphan Advisor",
        system_prompt: "You are a test advisor",
        llm_model: @llm_model
      )
      assert_not advisor.valid?
      assert_includes advisor.errors[:account], "can't be blank"
    end
  end

  # Association tests
  test "belongs to account" do
    advisor = Advisor.new
    assert_respond_to advisor, :account
  end

  test "belongs to llm_model" do
    advisor = Advisor.new
    assert_respond_to advisor, :llm_model
  end

  test "has many council_advisors" do
    advisor = Advisor.new
    assert_respond_to advisor, :council_advisors
  end

  test "has many councils through council_advisors" do
    advisor = Advisor.new
    assert_respond_to advisor, :councils
  end

  test "has many messages as sender polymorphic association" do
    advisor = Advisor.new
    assert_respond_to advisor, :messages
  end

  test "dependent destroy removes associated council_advisors" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    user = @account.users.create!(email: "test@example.com", password: "password123")
    space = @account.spaces.create!(name: "Test Space")
    council = @account.councils.create!(name: "Test Council", user: user, space: space)
    advisor.council_advisors.create!(council: council, position: 0)
    assert_difference("CouncilAdvisor.count", -1) do
      advisor.destroy
    end
  end

  # Scope tests
  test "global scope returns only global advisors" do
    @account.advisors.create!(
      name: "Global Advisor",
      system_prompt: "You are global",
      llm_model: @llm_model,
      global: true
    )
    @account.advisors.create!(
      name: "Custom Advisor",
      system_prompt: "You are custom",
      llm_model: @llm_model,
      global: false
    )
    assert_equal 1, Advisor.global.count
    assert Advisor.global.all?(&:global)
  end

  test "custom scope returns only non-global advisors" do
    @account.advisors.create!(
      name: "Global Advisor",
      system_prompt: "You are global",
      llm_model: @llm_model,
      global: true
    )
    @account.advisors.create!(
      name: "Custom Advisor",
      system_prompt: "You are custom",
      llm_model: @llm_model,
      global: false
    )
    assert_equal 1, Advisor.custom.count
    assert Advisor.custom.none?(&:global)
  end

  test "belongs to council (optional)" do
    advisor = Advisor.new
    assert_respond_to advisor, :council
  end

  test "valid as simple advisor with council_id, name, account, and model" do
    user = @account.users.create!(email: "test@example.com", password: "password123")
    space = @account.spaces.create!(name: "Test Space")
    council = @account.councils.create!(name: "Test Council", user: user, space: space)

    advisor = @account.advisors.new(
      name: "Simple Advisor",
      council: council,
      llm_model: @llm_model,
      system_prompt: "You are a simple advisor"
    )
    assert advisor.valid?
    assert advisor.simple?
  end

  test "non-simple advisor requires system_prompt and llm_model" do
    advisor = @account.advisors.new(
      name: "Full Advisor"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:system_prompt], "can't be blank"
    assert_includes advisor.errors[:llm_model], "can't be blank"
  end

  test "delegates provider to llm_model" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    assert_equal @provider, advisor.provider
  end

  test "delegates provider_type to llm_model" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    assert_equal "openai", advisor.provider_type
  end
end
