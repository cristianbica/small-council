# test/services/commands/invite_command_test.rb
require "test_helper"

class Commands::InviteCommandTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-cmd-account")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
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

    @scribe = @account.advisors.create!(
      name: "Scribe",
      system_prompt: "You are the scribe.",
      space: @space,
      is_scribe: true,
      llm_model: @llm_model
    )

    @advisor1 = @account.advisors.create!(
      name: "Strategic Advisor",
      system_prompt: "You are strategic.",
      space: @space,
      llm_model: @llm_model
    )

    @advisor2 = @account.advisors.create!(
      name: "Technical Expert",
      system_prompt: "You are technical.",
      space: @space,
      llm_model: @llm_model
    )

    # Create conversation with participants in one operation
    @conversation = Conversation.new(
      title: "Test Conversation",
      user: @user,
      account: @account,
      conversation_type: :adhoc,
      roe_type: :open
    )

    # Add scribe as participant first
    @conversation.conversation_participants.build(
      advisor: @scribe,
      role: :scribe,
      account: @account
    )

    # Add first advisor
    @conversation.conversation_participants.build(
      advisor: @advisor1,
      role: :advisor,
      account: @account
    )

    @conversation.save!
  end

  test "valid with @mention argument" do
    cmd = Commands::InviteCommand.new([ "@strategic_advisor" ])
    assert cmd.valid?
    assert_empty cmd.errors
  end

  test "invalid without arguments" do
    cmd = Commands::InviteCommand.new([])
    assert_not cmd.valid?
    assert_includes cmd.errors, "Usage: /invite @advisor_name"
  end

  test "invalid without @ prefix" do
    cmd = Commands::InviteCommand.new([ "advisor" ])
    assert_not cmd.valid?
    assert_includes cmd.errors, "Please mention an advisor with @advisor_name"
  end

  test "execute adds advisor to conversation" do
    advisor3 = @account.advisors.create!(
      name: "New Advisor",
      system_prompt: "You are new.",
      space: @space,
      llm_model: @llm_model
    )

    cmd = Commands::InviteCommand.new([ "@new_advisor" ])
    result = cmd.execute(conversation: @conversation, user: @user)

    assert result[:success], "Expected success but got: #{result[:message]}"
    assert_includes result[:message], "New Advisor has been invited"
    assert_includes @conversation.advisors.reload, advisor3
  end

  test "execute returns error for non-existent advisor" do
    cmd = Commands::InviteCommand.new([ "@nonexistent" ])
    result = cmd.execute(conversation: @conversation, user: @user)

    assert_not result[:success]
    assert_includes result[:message], "not found"
  end

  test "execute returns error when advisor already in conversation" do
    cmd = Commands::InviteCommand.new([ "@Strategic_Advisor" ])
    result = cmd.execute(conversation: @conversation, user: @user)

    assert_not result[:success], "Expected failure but got: #{result[:message]}"
    assert_includes result[:message].downcase, "already"
  end

  test "execute returns error when trying to invite scribe" do
    cmd = Commands::InviteCommand.new([ "@scribe" ])
    result = cmd.execute(conversation: @conversation, user: @user)

    assert_not result[:success]
    assert_includes result[:message], "Scribe is automatically present"
  end

  test "execute is case-insensitive for advisor names" do
    advisor3 = @account.advisors.create!(
      name: "New Advisor",
      system_prompt: "You are new.",
      space: @space,
      llm_model: @llm_model
    )

    cmd = Commands::InviteCommand.new([ "@NEW_ADVISOR" ])
    result = cmd.execute(conversation: @conversation, user: @user)

    assert result[:success], "Expected success but got: #{result[:message]}"
    assert_includes result[:message], "New Advisor"
  end

  test "execute handles names with spaces and dashes" do
    advisor3 = @account.advisors.create!(
      name: "Data Science Expert",
      system_prompt: "You are a data scientist.",
      space: @space,
      llm_model: @llm_model
    )

    cmd = Commands::InviteCommand.new([ "@data_science_expert" ])
    result = cmd.execute(conversation: @conversation, user: @user)

    assert result[:success], "Expected success but got: #{result[:message]}"
    assert_includes @conversation.advisors.reload, advisor3
  end
end
