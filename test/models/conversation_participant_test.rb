# test/models/conversation_participant_test.rb
require "test_helper"
require "securerandom"

class ConversationParticipantTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @space = spaces(:one)
    ActsAsTenant.current_tenant = @account

    # Create provider and LLM model for advisors
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    llm_model = provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    # Use the auto-created scribe
    @scribe = @space.scribe_advisor

    # Create regular advisors
    @advisor1 = @account.advisors.create!(
      name: "Strategic Advisor",
      system_prompt: "You are strategic.",
      space: @space,
      is_scribe: false,
      llm_model: llm_model
    )

    @advisor2 = @account.advisors.create!(
      name: "Technical Expert",
      system_prompt: "You are technical.",
      space: @space,
      is_scribe: false,
      llm_model: llm_model
    )

    # Create a conversation
    @conversation = @account.conversations.create!(
      title: "Test Conversation",
      user: users(:one),
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )

    # Add initial advisor to satisfy validation (for update validation)
    @conversation.conversation_participants.create!(
      advisor: @advisor1,
      role: :advisor,
      position: 0
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "valid conversation participant" do
    # Create a new advisor for this test (advisor1 is already in the conversation from setup)
    new_advisor = @account.advisors.create!(
      name: "Valid Test Advisor",
      system_prompt: "You are a test advisor",
      space: @space,
      is_scribe: false,
      llm_model: @advisor1.llm_model
    )
    participant = @conversation.conversation_participants.build(
      advisor: new_advisor,
      role: :advisor,
      position: 1
    )
    assert participant.valid?
  end

  test "requires conversation" do
    participant = ConversationParticipant.new(
      advisor: @advisor1,
      role: :advisor
    )
    assert_not participant.valid?
    assert_includes participant.errors[:conversation], "must exist"
  end

  test "requires advisor" do
    participant = @conversation.conversation_participants.build(
      role: :advisor
    )
    assert_not participant.valid?
    assert_includes participant.errors[:advisor], "must exist"
  end

  test "role defaults to advisor" do
    # Create a new advisor for this test (advisor1 is already in the conversation)
    new_advisor = @account.advisors.create!(
      name: "Role Test Advisor",
      system_prompt: "You are a test advisor",
      space: @space,
      is_scribe: false,
      llm_model: @advisor1.llm_model
    )
    participant = @conversation.conversation_participants.build(
      advisor: new_advisor
    )
    # Role should default to "advisor"
    assert_equal "advisor", participant.role
    assert participant.valid?
  end

  test "enforces unique advisor per conversation" do
    # Use advisor2 since advisor1 is already added in setup
    @conversation.conversation_participants.create!(
      advisor: @advisor2,
      role: :advisor
    )

    duplicate = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:advisor_id], "is already a participant in this conversation"
  end

  test "advisor role is default" do
    # Create a new advisor for this test
    new_advisor = @account.advisors.create!(
      name: "New Advisor",
      system_prompt: "You are new.",
      space: @space,
      is_scribe: false,
      llm_model: @advisor1.llm_model
    )
    participant = @conversation.conversation_participants.create!(advisor: new_advisor)
    assert_equal "advisor", participant.role
  end

  test "scribe role can be set" do
    # Create a new conversation for this test
    conv2 = @account.conversations.create!(
      title: "Test Conversation 2",
      user: users(:one),
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conv2.conversation_participants.create!(
      advisor: @advisor1,
      role: :advisor,
      position: 0
    )
    participant = conv2.conversation_participants.create!(
      advisor: @scribe,
      role: :scribe
    )
    assert_equal "scribe", participant.role
    assert participant.scribe?
  end

  test "sets account from conversation before create" do
    # Use advisor2 since advisor1 is already added in setup
    participant = @conversation.conversation_participants.create!(advisor: @advisor2)
    assert_equal @account.id, participant.account_id
  end

  test "ordered scope returns by position then created_at" do
    # Use advisor2, create at different positions
    p2 = @conversation.conversation_participants.create!(advisor: @advisor2, position: 2)

    # advisor1 is at position 0 from setup
    p1 = @conversation.conversation_participants.find_by(advisor: @advisor1)

    ordered = @conversation.conversation_participants.ordered
    assert_equal p1, ordered.first
    assert_equal p2, ordered.last
  end

  test "initialization without advisor does not crash and defaults tools to deny" do
    participant = nil

    assert_nothing_raised do
      participant = ConversationParticipant.new
    end

    assert participant.tools.all? { |entry| entry["policy"] == "deny" }
  end

  test "scribe defaults allow memories and browse web tools" do
    participant = @conversation.conversation_participants.build(
      advisor: @scribe,
      role: :scribe,
      position: 3
    )

    tool_by_ref = participant.tools.index_by { |entry| entry["ref"] }
    AI.expand_tools([ "memories/*", "internet/browse_web" ]).each do |ref|
      assert_equal "allow", tool_by_ref[ref]["policy"]
    end
  end

  test "explicit tool policy overrides scribe default" do
    participant = @conversation.conversation_participants.build(
      advisor: @scribe,
      role: :scribe,
      position: 3,
      tools: [ { "ref" => "internet/browse_web", "policy" => "deny" } ]
    )

    assert participant.valid?

    tool_by_ref = participant.tools.index_by { |entry| entry["ref"] }
    assert_equal "deny", tool_by_ref["internet/browse_web"]["policy"]
  end

  test "participant accepts llm model that belongs to account" do
    participant = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor,
      position: 2,
      llm_model: @advisor1.llm_model
    )

    assert participant.valid?
  end

  test "effective_llm_model prefers participant llm_model" do
    extra_model = @advisor1.llm_model.provider.llm_models.create!(
      account: @account,
      name: "Participant Preferred",
      identifier: "participant-preferred-#{SecureRandom.hex(4)}"
    )

    participant = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor,
      position: 2,
      llm_model: extra_model
    )

    assert_equal extra_model, participant.effective_llm_model
  end

  test "effective_llm_model falls back to advisor model" do
    participant = @conversation.conversation_participants.build(
      advisor: @advisor1,
      role: :advisor,
      position: 2,
      llm_model: nil
    )

    assert_equal @advisor1.llm_model, participant.effective_llm_model
  end

  test "effective_llm_model falls back to account default model" do
    default_model = @advisor1.llm_model.provider.llm_models.create!(
      account: @account,
      name: "Account Default",
      identifier: "account-default-#{SecureRandom.hex(4)}"
    )
    @account.update!(default_llm_model: default_model)

    participant = ConversationParticipant.new(account: @account, advisor: nil, llm_model: nil)

    assert_equal default_model, participant.effective_llm_model
  end

  test "effective_llm_model falls back to first enabled account model" do
    @account.update!(default_llm_model: nil)
    @advisor1.llm_model.provider.llm_models.create!(
      account: @account,
      name: "Enabled Fallback",
      identifier: "enabled-fallback-#{SecureRandom.hex(4)}"
    )
    expected = @account.llm_models.enabled.first

    participant = ConversationParticipant.new(account: @account, advisor: nil, llm_model: nil)

    assert_equal expected, participant.effective_llm_model
  end

  test "effective_llm_model returns nil when no sources exist" do
    participant = ConversationParticipant.new(account: nil, advisor: nil, llm_model: nil)

    assert_nil participant.effective_llm_model
  end

  test "participant rejects llm model from another account" do
    other_account = Account.create!(name: "Other Account", slug: "other-account-#{SecureRandom.hex(4)}")
    other_model = nil

    ActsAsTenant.with_tenant(other_account) do
      other_provider = other_account.providers.create!(
        name: "Other Provider",
        provider_type: "openai",
        api_key: "other-test-key"
      )
      other_model = other_provider.llm_models.create!(
        account: other_account,
        name: "Other Model",
        identifier: "other-model"
      )
    end

    ActsAsTenant.current_tenant = @account

    participant = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor,
      position: 2,
      llm_model: other_model
    )

    assert_not participant.valid?
    assert_includes participant.errors[:llm_model], "must belong to this account"
  end

  test "set_account_from_conversation does nothing without conversation" do
    participant = ConversationParticipant.new(account: @account)

    assert_nothing_raised do
      participant.send(:set_account_from_conversation)
    end

    assert_equal @account.id, participant.account_id
  end

  test "llm_model_belongs_to_account returns early when llm_model_id is blank" do
    participant = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor,
      position: 4,
      llm_model_id: nil
    )

    participant.send(:llm_model_belongs_to_account)

    assert_empty participant.errors[:llm_model]
  end

  test "llm_model_belongs_to_account returns early when account is blank" do
    participant = ConversationParticipant.new(
      advisor: @advisor2,
      role: :advisor,
      llm_model_id: @advisor1.llm_model_id,
      account: nil
    )

    participant.send(:llm_model_belongs_to_account)

    assert_empty participant.errors[:llm_model]
  end

  test "llm_model_belongs_to_account does not add error when model belongs to account" do
    participant = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor,
      position: 5,
      llm_model: @advisor1.llm_model
    )

    participant.send(:llm_model_belongs_to_account)

    assert_empty participant.errors[:llm_model]
  end

  test "llm_model_belongs_to_account adds error when model does not belong to account" do
    other_account = Account.create!(name: "External Account", slug: "external-account-#{SecureRandom.hex(4)}")
    other_model = nil

    ActsAsTenant.with_tenant(other_account) do
      other_provider = other_account.providers.create!(
        name: "External Provider",
        provider_type: "openai",
        api_key: "external-key"
      )
      other_model = other_provider.llm_models.create!(
        account: other_account,
        name: "External Model",
        identifier: "external-model"
      )
    end
    ActsAsTenant.current_tenant = @account

    participant = @conversation.conversation_participants.build(
      advisor: @advisor2,
      role: :advisor,
      position: 5,
      llm_model_id: other_model.id
    )

    participant.send(:llm_model_belongs_to_account)

    assert_includes participant.errors[:llm_model], "must belong to this account"
  end
end
