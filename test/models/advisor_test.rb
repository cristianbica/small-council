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
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a helpful test advisor",
      llm_model: @llm_model,
      space: space
    )
    assert advisor.valid?
  end

  test "invalid without name" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.new(
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:name], "can't be blank"
  end

  test "invalid without system_prompt for non-simple advisor" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.new(
      name: "Test Advisor",
      llm_model: @llm_model,
      space: space
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:system_prompt], "can't be blank"
  end

  test "valid without llm_model - falls back to account default" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      space: space
    )
    # Advisor is valid without llm_model because it will use account default
    assert advisor.valid?
    assert advisor.effective_llm_model.present?
  end

  test "invalid without account" do
    space = @account.spaces.create!(name: "Test Space")
    ActsAsTenant.without_tenant do
      advisor = Advisor.new(
        name: "Orphan Advisor",
        system_prompt: "You are a test advisor",
        llm_model: @llm_model,
        space: space
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
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )
    user = @account.users.create!(email: "test@example.com", password: "password123")
    council = @account.councils.create!(name: "Test Council", user: user, space: space)
    advisor.council_advisors.create!(council: council, position: 0)
    assert_difference("CouncilAdvisor.count", -1) do
      advisor.destroy
    end
  end

  test "belongs to space" do
    advisor = Advisor.new
    assert_respond_to advisor, :space
  end

  test "valid without space (space is optional)" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    assert advisor.valid?, "Advisor should be valid without space (optional association)"
  end

  test "valid with space, name, system_prompt, and llm_model" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.new(
      name: "Test Advisor",
      space: space,
      llm_model: @llm_model,
      system_prompt: "You are a helpful advisor"
    )
    assert advisor.valid?
  end

  test "advisor requires system_prompt but llm_model is optional" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.new(
      name: "Full Advisor",
      space: space
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:system_prompt], "can't be blank"
    # llm_model is now optional - it falls back to account default
    assert_not_includes advisor.errors[:llm_model], "can't be blank"
  end

  test "delegates provider to llm_model" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )
    assert_equal @provider, advisor.provider
  end

  test "delegates provider_type to llm_model" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )
    assert_equal "openai", advisor.provider_type
  end

  # Scribe tests (is_scribe flag)
  test "scribe? returns true when is_scribe is true" do
    space = @account.spaces.create!(name: "Test Space")
    scribe = @account.advisors.create!(
      name: "The Scribe",
      system_prompt: "You are the scribe.",
      space: space,
      is_scribe: true
    )
    assert scribe.scribe?
  end

  test "scribe? returns false when is_scribe is false" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.create!(
      name: "Regular Advisor",
      system_prompt: "You are a regular advisor.",
      space: space,
      is_scribe: false
    )
    assert_not advisor.scribe?
  end

  test "scribe? returns false when is_scribe is nil" do
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.create!(
      name: "Another Advisor",
      system_prompt: "You are an advisor.",
      space: space
    )
    assert_not advisor.scribe?
  end

  test "scribe does not require system_prompt" do
    space = @account.spaces.create!(name: "Test Space")
    scribe = @account.advisors.new(
      name: "Scribe Without Prompt",
      space: space,
      is_scribe: true
    )
    assert scribe.valid?
  end

  test "has many conversation_participants" do
    advisor = Advisor.new
    assert_respond_to advisor, :conversation_participants
  end

  test "has many conversations through conversation_participants" do
    advisor = Advisor.new
    assert_respond_to advisor, :conversations
  end
end
