# test/models/conversation_participant_test.rb
require "test_helper"

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

    # Create scribe advisor
    @scribe = @account.advisors.create!(
      name: "Scribe",
      system_prompt: "You are the scribe.",
      space: @space,
      is_scribe: true,
      llm_model: llm_model
    )

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

  test "advisors_only scope excludes scribes" do
    # Use advisor2 since advisor1 is already added in setup
    @conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor)
    @conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    assert_equal 2, @conversation.conversation_participants.advisors_only.count
    assert_includes @conversation.conversation_participants.advisors_only.map(&:advisor), @advisor1
    assert_includes @conversation.conversation_participants.advisors_only.map(&:advisor), @advisor2
    assert_not_includes @conversation.conversation_participants.advisors_only.map(&:advisor), @scribe
  end

  test "scribes_only scope includes only scribes" do
    @conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor)
    @conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    assert_equal 1, @conversation.conversation_participants.scribes_only.count
    assert_includes @conversation.conversation_participants.scribes_only.map(&:advisor), @scribe
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
end
