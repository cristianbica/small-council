require "test_helper"

class AdvisorTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-advisors")
  end

  # Validation tests
  test "valid with all required attributes" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a helpful test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert advisor.valid?
  end

  test "invalid without name" do
    advisor = @account.advisors.new(
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:name], "can't be blank"
  end

  test "invalid without system_prompt" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:system_prompt], "can't be blank"
  end

  test "invalid without model_provider" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_id: "gpt-4"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:model_provider], "can't be blank"
  end

  test "invalid without model_id" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:model_id], "can't be blank"
  end

  test "invalid without account" do
    advisor = Advisor.new(
      name: "Orphan Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:account], "can't be blank"
  end

  # Association tests
  test "belongs to account" do
    advisor = Advisor.new
    assert_respond_to advisor, :account
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
      model_provider: "openai",
      model_id: "gpt-4"
    )
    user = @account.users.create!(email: "test@example.com")
    council = @account.councils.create!(name: "Test Council", user: user)
    advisor.council_advisors.create!(council: council, position: 0)
    assert_difference("CouncilAdvisor.count", -1) do
      advisor.destroy
    end
  end

  # Enum tests
  test "model_provider enum values" do
    assert_equal({ "openai" => "openai", "anthropic" => "anthropic", "gemini" => "gemini" }, Advisor.model_providers)
  end

  test "can set model_provider to openai" do
    advisor = @account.advisors.create!(
      name: "OpenAI Advisor",
      system_prompt: "You are an OpenAI advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert advisor.openai?
  end

  test "can set model_provider to anthropic" do
    advisor = @account.advisors.create!(
      name: "Anthropic Advisor",
      system_prompt: "You are an Anthropic advisor",
      model_provider: "anthropic",
      model_id: "claude-3"
    )
    assert advisor.anthropic?
  end

  test "can set model_provider to gemini" do
    advisor = @account.advisors.create!(
      name: "Gemini Advisor",
      system_prompt: "You are a Gemini advisor",
      model_provider: "gemini",
      model_id: "gemini-pro"
    )
    assert advisor.gemini?
  end

  test "model_provider enum methods work" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    assert advisor.openai?
    assert_not advisor.anthropic?

    advisor.anthropic!
    assert advisor.anthropic?
    assert_not advisor.openai?
  end

  test "invalid model_provider raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.advisors.create!(
        name: "Invalid Provider Advisor",
        system_prompt: "You are a test advisor",
        model_provider: "invalid_provider",
        model_id: "gpt-4"
      )
    end
  end

  # Scope tests
  test "global scope returns only global advisors" do
    @account.advisors.create!(
      name: "Global Advisor",
      system_prompt: "You are global",
      model_provider: "openai",
      model_id: "gpt-4",
      global: true
    )
    @account.advisors.create!(
      name: "Custom Advisor",
      system_prompt: "You are custom",
      model_provider: "openai",
      model_id: "gpt-4",
      global: false
    )
    assert_equal 1, Advisor.global.count
    assert Advisor.global.all?(&:global)
  end

  test "custom scope returns only non-global advisors" do
    @account.advisors.create!(
      name: "Global Advisor",
      system_prompt: "You are global",
      model_provider: "openai",
      model_id: "gpt-4",
      global: true
    )
    @account.advisors.create!(
      name: "Custom Advisor",
      system_prompt: "You are custom",
      model_provider: "openai",
      model_id: "gpt-4",
      global: false
    )
    assert_equal 1, Advisor.custom.count
    assert Advisor.custom.none?(&:global)
  end
end
