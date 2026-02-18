require "test_helper"

class ScribeCoordinatorTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @user = users(:one)
    set_tenant(@account)

    # Create a council with advisors
    @council = @account.councils.create!(name: "Test Council", user: @user)

    # Create advisors for the council (add through join table)
    @advisor1 = @account.advisors.create!(
      name: "Test Advisor One",
      system_prompt: "You are advisor one",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    @advisor2 = @account.advisors.create!(
      name: "Test Advisor Two",
      system_prompt: "You are advisor two",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    @council.advisors << [ @advisor1, @advisor2 ]

    # Create a conversation
    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Test Conversation",
      rules_of_engagement: :round_robin
    )
  end

  test "round_robin returns first advisor initially" do
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders

    assert_equal [ @advisor1 ], responders
  end

  test "round_robin cycles to next advisor" do
    @conversation.mark_advisor_spoken(@advisor1.id)

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders

    assert_equal [ @advisor2 ], responders
  end

  test "round_robin wraps back to first" do
    @conversation.mark_advisor_spoken(@advisor2.id)

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders

    assert_equal [ @advisor1 ], responders
  end

  test "silent mode returns empty" do
    @conversation.update!(rules_of_engagement: :silent)

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders

    assert_empty responders
  end

  test "consensus returns all advisors" do
    @conversation.update!(rules_of_engagement: :consensus)

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders

    assert_equal 2, responders.count
    assert_includes responders, @advisor1
    assert_includes responders, @advisor2
  end

  test "on_demand returns empty without mentions" do
    @conversation.update!(rules_of_engagement: :on_demand)
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Hello without mentions"
    )

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)

    assert_empty responders
  end

  test "parses @mention and returns matching advisor" do
    @advisor1.update!(name: "Test Advisor")
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Hey @Test_Advisor, help me out"
    )

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)

    assert_equal [ @advisor1 ], responders
  end

  test "@mentions take priority over round_robin" do
    @conversation.mark_advisor_spoken(@advisor1.id) # Would normally get advisor2
    @advisor1.update!(name: "Alpha")
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "@Alpha please respond"
    )

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)

    assert_equal [ @advisor1 ], responders # Got advisor1 via mention, not advisor2 via round_robin
  end

  test "handles multiple @mentions" do
    @advisor1.update!(name: "Advisor One")
    @advisor2.update!(name: "Advisor Two")
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "@Advisor_One and @Advisor_Two please help"
    )

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)

    assert_equal 2, responders.count
  end

  test "moderated returns advisor with fewest messages" do
    @conversation.update!(rules_of_engagement: :moderated)

    # Create a message from advisor1
    @account.messages.create!(
      conversation: @conversation,
      sender: @advisor1,
      role: "advisor",
      content: "Test message"
    )

    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders

    # Should return advisor2 who has fewer messages
    assert_equal [ @advisor2 ], responders
  end

  test "returns empty when council has no advisors" do
    # Create new council without advisors
    empty_council = @account.councils.create!(name: "Empty Council", user: @user)
    empty_conversation = @account.conversations.create!(
      council: empty_council,
      user: @user,
      title: "Empty Conversation"
    )

    coordinator = ScribeCoordinator.new(empty_conversation)
    responders = coordinator.determine_responders

    assert_empty responders
  end
end
