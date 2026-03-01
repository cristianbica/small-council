# test/models/advisor_comprehensive_test.rb
require "test_helper"

class AdvisorComprehensiveTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-advisor-comprehensive")
    set_tenant(@account)
    @space = @account.spaces.create!(name: "Test Space")

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

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "valid with name, system_prompt, and account" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      llm_model: @llm_model,
      space: @space
    )
    assert advisor.valid?
  end

  test "invalid without name" do
    advisor = @account.advisors.new(
      system_prompt: "You are a test advisor.",
      llm_model: @llm_model,
      space: @space
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:name], "can't be blank"
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      advisor = Advisor.new(
        name: "Test Advisor",
        system_prompt: "You are a test advisor.",
        llm_model: @llm_model,
        space: @space
      )
      assert_not advisor.valid?
      assert_includes advisor.errors[:account], "can't be blank"
    end
  end

  test "invalid without system_prompt for non-scribe" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      llm_model: @llm_model,
      space: @space
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:system_prompt], "can't be blank"
  end

  test "valid without system_prompt for scribe" do
    advisor = @account.advisors.new(
      name: "Scribe",
      space: @space,
      is_scribe: true,
      llm_model: @llm_model
    )
    assert advisor.valid?
  end

  test "valid without llm_model" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space
    )
    assert advisor.valid?
  end

  test "invalid when llm_model belongs to different account" do
    # Need to create other account without tenant scoping affecting it
    other_account = nil
    other_model = nil

    ActsAsTenant.without_tenant do
      other_account = Account.create!(name: "Other Account", slug: "other-account")
      other_provider = other_account.providers.create!(
        name: "Other Provider",
        provider_type: "openai",
        api_key: "test-key"
      )
      other_model = other_provider.llm_models.create!(
        account: other_account,
        name: "GPT-4",
        identifier: "gpt-4"
      )
    end

    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      llm_model: other_model,
      space: @space
    )
    assert_not advisor.valid?
    assert_includes advisor.errors[:llm_model], "must belong to this account"
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  # ============================================================================
  # SCRIBE METHODS
  # ============================================================================

  test "scribe? returns true when is_scribe is true" do
    advisor = @account.advisors.new(is_scribe: true)
    assert advisor.scribe?
  end

  test "scribe? returns false when is_scribe is false" do
    advisor = @account.advisors.new(is_scribe: false)
    assert_not advisor.scribe?
  end

  test "scribe? returns false when is_scribe is nil" do
    advisor = @account.advisors.new
    assert_not advisor.scribe?
  end

  # ============================================================================
  # LLM MODEL METHODS
  # ============================================================================

  test "effective_llm_model returns advisor's model when set" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert_equal @llm_model, advisor.effective_llm_model
  end

  test "effective_llm_model falls back to account default" do
    # Set account default model
    @account.update!(default_llm_model: @llm_model)

    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space
    )
    assert_equal @llm_model, advisor.effective_llm_model
  end

  test "effective_llm_model falls back to first enabled account model" do
    # Don't set account default, use first enabled model
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space
    )
    # Since @llm_model is the only enabled model
    assert_equal @llm_model, advisor.effective_llm_model
  end

  test "effective_llm_model returns nil when no models available" do
    # Delete all models from account
    @account.llm_models.destroy_all

    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space
    )
    assert_nil advisor.effective_llm_model
  end

  test "llm_model_configured? returns true when model is set" do
    advisor = @account.advisors.new(
      llm_model: @llm_model
    )
    assert advisor.llm_model_configured?
  end

  test "llm_model_configured? returns true when effective model is available" do
    @account.update!(default_llm_model: @llm_model)

    advisor = @account.advisors.new
    assert advisor.llm_model_configured?
  end

  test "llm_model_configured? returns false when no model available" do
    @account.llm_models.destroy_all
    @account.update!(default_llm_model: nil)

    advisor = @account.advisors.new
    assert_not advisor.llm_model_configured?
  end

  test "llm_model_configured? returns true for scribe regardless of model" do
    @account.llm_models.destroy_all
    @account.update!(default_llm_model: nil)

    scribe = @account.advisors.new(is_scribe: true)
    assert scribe.llm_model_configured?
  end

  test "delegates provider to effective_llm_model" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert_equal @provider, advisor.provider
  end

  test "delegates provider_type to effective_llm_model" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert_equal "openai", advisor.provider_type
  end

  test "provider returns nil when no effective_llm_model" do
    # Create situation where no LLM model is available
    # First remove all models from the account
    @account.llm_models.destroy_all
    @account.update!(default_llm_model: nil)

    # Reload to clear any cached data
    @account.reload

    advisor = @account.advisors.new
    # If no models exist, provider should be nil
    assert_nil advisor.effective_llm_model
    assert_nil advisor.provider
  end

  test "provider_type returns nil when no effective_llm_model" do
    # Create situation where no LLM model is available
    @account.llm_models.destroy_all
    @account.update!(default_llm_model: nil)
    @account.reload

    advisor = @account.advisors.new
    assert_nil advisor.effective_llm_model
    assert_nil advisor.provider_type
  end

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "belongs to account" do
    advisor = Advisor.new
    assert_respond_to advisor, :account
  end

  test "belongs to space" do
    advisor = Advisor.new
    assert_respond_to advisor, :space
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

  test "has many conversation_participants" do
    advisor = Advisor.new
    assert_respond_to advisor, :conversation_participants
  end

  test "has many conversations through conversation_participants" do
    advisor = Advisor.new
    assert_respond_to advisor, :conversations
  end

  test "has many messages as sender" do
    advisor = Advisor.new
    assert_respond_to advisor, :messages
  end

  test "council_advisors are dependent destroy" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    user = @account.users.create!(email: "test@example.com", password: "password123")
    council = @account.councils.create!(name: "Test Council", user: user, space: @space)
    advisor.council_advisors.create!(council: council, position: 0)

    assert_difference("CouncilAdvisor.count", -1) do
      advisor.destroy
    end
  end

  test "conversation_participants are dependent destroy" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    user = @account.users.create!(email: "test2@example.com", password: "password123")
    conversation = @account.conversations.create!(
      title: "Test",
      user: user,
      conversation_type: :adhoc
    )
    conversation.conversation_participants.create!(advisor: advisor, role: :advisor, position: 0)

    assert_difference("ConversationParticipant.count", -1) do
      advisor.destroy
    end
  end

  test "messages as sender prevent advisor destroy" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    user = @account.users.create!(email: "test3@example.com", password: "password123")
    conversation = @account.conversations.create!(
      title: "Test",
      user: user,
      conversation_type: :adhoc
    )
    @account.messages.create!(
      conversation: conversation,
      sender: advisor,
      role: "advisor",
      content: "Test message"
    )

    # With dependent: :restrict_with_error, advisor cannot be destroyed if it has messages
    assert_no_difference("Message.count") do
      assert_equal false, advisor.destroy
    end
    assert advisor.errors[:base].any? { |e| e.include?("Cannot delete") || e.include?("dependent") }
  end

  # ============================================================================
  # ENCRYPTION
  # ============================================================================

  test "encrypts system_prompt - plaintext readable" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "Secret prompt content",
      space: @space,
      llm_model: @llm_model
    )
    # Verify we can read the plaintext (encryption is transparent)
    assert_equal "Secret prompt content", advisor.system_prompt
  end

  test "encrypts short_description - plaintext readable" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      short_description: "Secret description",
      space: @space,
      llm_model: @llm_model
    )
    # Verify we can read the plaintext (encryption is transparent)
    assert_equal "Secret description", advisor.short_description
  end

  # ============================================================================
  # SPACE ASSOCIATION
  # ============================================================================

  test "space is optional" do
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      llm_model: @llm_model
    )
    assert advisor.valid?
  end

  test "belongs to space when set" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert_equal @space, advisor.space
  end

  # ============================================================================
  # ADVISOR WITHOUT SPACE
  # ============================================================================

  test "advisor without space can be created" do
    advisor = @account.advisors.create!(
      name: "Spaceless Advisor",
      system_prompt: "You are a spaceless advisor.",
      llm_model: @llm_model
    )
    assert_nil advisor.space
    assert advisor.valid?
  end

  test "advisor without space can be added to council" do
    advisor = @account.advisors.create!(
      name: "Spaceless Advisor",
      system_prompt: "You are a spaceless advisor.",
      llm_model: @llm_model
    )
    user = @account.users.create!(email: "test4@example.com", password: "password123")
    council = @account.councils.create!(name: "Test Council", user: user, space: @space)

    council.advisors << advisor
    assert_includes council.advisors, advisor
  end

  # ============================================================================
  # COMPREHENSIVE ADVISOR SCENARIOS
  # ============================================================================

  test "advisor with very long name is valid" do
    advisor = @account.advisors.new(
      name: "A" * 255,
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert advisor.valid?
  end

  test "advisor with special characters in name is valid" do
    advisor = @account.advisors.create!(
      name: "Advisor-Name_123 (Test)",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert advisor.valid?
    assert_equal "Advisor-Name_123 (Test)", advisor.name
  end

  test "advisor with long system_prompt is valid" do
    long_prompt = "You are a helpful assistant. " * 100
    advisor = @account.advisors.new(
      name: "Test Advisor",
      system_prompt: long_prompt,
      space: @space,
      llm_model: @llm_model
    )
    assert advisor.valid?
  end

  test "advisor name uniqueness is not enforced at model level" do
    # Create first advisor
    @account.advisors.create!(
      name: "Duplicate Name",
      system_prompt: "First advisor.",
      space: @space,
      llm_model: @llm_model
    )

    # Create second advisor with same name
    second = @account.advisors.new(
      name: "Duplicate Name",
      system_prompt: "Second advisor.",
      space: @space,
      llm_model: @llm_model
    )
    assert second.valid?  # No uniqueness validation on name
  end

  test "advisor can be assigned to multiple councils" do
    user = @account.users.create!(email: "test5@example.com", password: "password123")
    council1 = @account.councils.create!(name: "Council 1", user: user, space: @space)
    council2 = @account.councils.create!(name: "Council 2", user: user, space: @space)

    advisor = @account.advisors.create!(
      name: "Multi-Council Advisor",
      system_prompt: "You are in multiple councils.",
      space: @space,
      llm_model: @llm_model
    )

    council1.advisors << advisor
    council2.advisors << advisor

    assert_includes advisor.councils, council1
    assert_includes advisor.councils, council2
  end

  test "advisor can participate in multiple conversations" do
    user = @account.users.create!(email: "test6@example.com", password: "password123")
    conv1 = @account.conversations.create!(
      title: "Conv 1",
      user: user,
      conversation_type: :adhoc
    )
    conv2 = @account.conversations.create!(
      title: "Conv 2",
      user: user,
      conversation_type: :adhoc
    )

    advisor = @account.advisors.create!(
      name: "Multi-Conv Advisor",
      system_prompt: "You are in multiple conversations.",
      space: @space,
      llm_model: @llm_model
    )

    conv1.conversation_participants.create!(advisor: advisor, role: :advisor, position: 0)
    conv2.conversation_participants.create!(advisor: advisor, role: :advisor, position: 0)

    assert_includes advisor.conversations, conv1
    assert_includes advisor.conversations, conv2
  end
end
