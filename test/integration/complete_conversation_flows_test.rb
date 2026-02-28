# test/integration/complete_conversation_flows_test.rb
require "test_helper"

class CompleteConversationFlowsTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")

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
  end

  # ============================================================================
  # ADHOC CONVERSATION LIFECYCLE
  # ============================================================================

  test "complete adhoc conversation lifecycle with Open RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    # Step 1: Create adhoc conversation
    assert_difference("Conversation.count", 1) do
      assert_difference("Message.count", 1) do
        post conversations_path, params: {
          conversation: {
            title: "Test Adhoc Conversation",
            initial_message: "Let's discuss the project",
            roe_type: "open",
            advisor_ids: [ @advisor1.id, @advisor2.id ]
          }
        }
      end
    end

    conversation = Conversation.last
    assert_redirected_to conversation_path(conversation)
    assert_equal "open", conversation.roe_type
    assert_equal "adhoc", conversation.conversation_type
    assert_equal 2, conversation.participant_advisors.count

    # Step 2: View conversation
    get conversation_path(conversation)
    assert_response :success
    assert_select "h1", conversation.title

    # Step 3: Post message with mention in Open RoE
    assert_enqueued_jobs 1, only: GenerateAdvisorResponseJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@strategic_advisor what do you think?" }
      }
    end
    assert_redirected_to conversation_path(conversation)

    # Step 4: Post message without mention (no responses in Open RoE)
    assert_no_enqueued_jobs do
      post conversation_messages_path(conversation), params: {
        message: { content: "What does everyone think?" }
      }
    end

    # Step 5: Finish conversation
    assert_enqueued_with(job: GenerateConversationSummaryJob) do
      post finish_conversation_path(conversation)
    end
    assert_redirected_to conversation_path(conversation)
    assert conversation.reload.concluding?

    # Step 6: Reject summary and continue
    post reject_summary_conversation_path(conversation)
    assert_redirected_to conversation_path(conversation)
    assert conversation.reload.active?
  end

  test "complete adhoc conversation lifecycle with Consensus RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create conversation with Consensus RoE
    post conversations_path, params: {
      conversation: {
        title: "Consensus Discussion",
        initial_message: "We need to make a decision",
        roe_type: "consensus",
        advisor_ids: [ @advisor1.id, @advisor2.id ]
      }
    }

    conversation = Conversation.last
    assert_equal "consensus", conversation.roe_type

    # In Consensus, all participants respond without mentions (including scribe)
    assert_enqueued_jobs 3, only: GenerateAdvisorResponseJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "What do you all think?" }
      }
    end
  end

  test "complete adhoc conversation lifecycle with Brainstorming RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    post conversations_path, params: {
      conversation: {
        title: "Brainstorming Session",
        initial_message: "Let's brainstorm ideas",
        roe_type: "brainstorming",
        advisor_ids: [ @advisor1.id, @advisor2.id ]
      }
    }

    conversation = Conversation.last
    assert_equal "brainstorming", conversation.roe_type

    # In Brainstorming, all participants respond (including scribe)
    assert_enqueued_jobs 3, only: GenerateAdvisorResponseJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "Brainstorm ideas for our product" }
      }
    end
  end

  # ============================================================================
  # COUNCIL MEETING LIFECYCLE
  # ============================================================================

  test "complete council meeting lifecycle" do
    sign_in_as(@user)
    set_tenant(@account)

    council = @account.councils.create!(
      name: "Strategy Council",
      user: @user,
      space: @space
    )
    council.advisors << @advisor1
    council.advisors << @advisor2

    # Step 1: Create council meeting
    assert_difference("Conversation.count", 1) do
      assert_difference("Message.count", 1) do
        post council_conversations_path(council), params: {
          conversation: {
            title: "Q4 Planning Meeting",
            initial_message: "Let's plan for Q4",
            roe_type: "consensus"
          }
        }
      end
    end

    conversation = Conversation.last
    assert_redirected_to conversation_path(conversation)
    assert_equal "council_meeting", conversation.conversation_type
    assert_equal council, conversation.council
    assert_equal 2, conversation.participant_advisors.count

    # Step 2: View council meeting
    get conversation_path(conversation)
    assert_response :success
    assert_select "h1", "Q4 Planning Meeting"

    # Step 3: Post message
    assert_enqueued_jobs 2, only: GenerateAdvisorResponseJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "What are our priorities?" }
      }
    end

    # Step 4: List council meetings
    get council_conversations_path(council)
    assert_response :success
    assert_select "h1", "#{council.name} Conversations"
    assert_select "h3", conversation.title

    # Step 5: Delete council meeting
    assert_difference("Conversation.count", -1) do
      delete conversation_path(conversation)
    end
    assert_redirected_to council_conversations_path(council)
  end

  # ============================================================================
  # SCRIBE FOLLOW-UP FLOW
  # ============================================================================

  test "scribe follow-up flow - 0 to 3 attempts" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Scribe Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      scribe_initiated_count: 0
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # Create a root message with pending advisor
    message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    # Simulate advisor response - should trigger scribe (count becomes 1)
    reply = conversation.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my analysis",
      parent_message: message,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conversation)
    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.advisor_responded(reply)
    end
    assert_equal 1, conversation.reload.scribe_initiated_count
  end

  test "scribe follow-up stops after 3 attempts" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Scribe Limit Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      scribe_initiated_count: 3
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conversation.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Reply",
      parent_message: message,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conversation)
    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end
    assert_equal 3, conversation.reload.scribe_initiated_count
  end

  # ============================================================================
  # @ALL MENTION EXPANSION FLOW
  # ============================================================================

  test "@all mention expands to all participants in Open RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "@all Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # @all includes all participants (2 advisors + scribe = 3)
    assert_enqueued_jobs 3, only: GenerateAdvisorResponseJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@all what are your thoughts?" }
      }
    end
  end

  test "@everyone mention expands to all participants in Open RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "@everyone Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # @everyone includes all participants (2 advisors + scribe = 3)
    assert_enqueued_jobs 3, only: GenerateAdvisorResponseJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@everyone please respond" }
      }
    end
  end

  # ============================================================================
  # DEPTH LIMIT ENFORCEMENT FLOW
  # ============================================================================

  test "depth limit enforcement in Open RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Depth Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      scribe_initiated_count: 3  # Disable scribe
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # Root message triggers reply (depth 0 -> depth 1)
    root_msg = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor help",
      pending_advisor_ids: [ @advisor1.id ]
    )

    # Advisor reply at depth 1
    reply = conversation.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Reply at depth 1",
      parent_message: root_msg,
      status: "complete"
    )

    # At depth 1 in Open RoE (max depth = 1), no new messages should be triggered
    lifecycle = ConversationLifecycle.new(conversation)
    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end
  end

  test "depth limit enforcement in Consensus RoE allows depth 2" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Depth Test Consensus",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :consensus,
      scribe_initiated_count: 3
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)

    # Messages at depth 2 should not trigger new responses
    root_msg = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root"
    )

    level1 = conversation.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Level 1",
      parent_message: root_msg,
      pending_advisor_ids: [ @advisor2.id ]
    )

    level2 = conversation.messages.create!(
      account: @account,
      sender: @advisor2,
      role: "advisor",
      content: "Level 2",
      parent_message: level1,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conversation)
    # At depth 2 (max depth in Consensus), no new messages
    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(level2)
    end
  end

  # ============================================================================
  # COMMAND EXECUTION FLOW
  # ============================================================================

  test "command execution flow - invite advisor" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Command Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # Invite new advisor via command
    assert_difference("ConversationParticipant.count", 1) do
      post conversation_messages_path(conversation), params: {
        message: { content: "/invite @technical_expert" }
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert_includes conversation.advisors.reload, @advisor2
  end

  test "command execution flow - invalid command shows error" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invalid Command Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # Invalid command without mention
    assert_difference("Message.where(role: :system).count", 1) do
      post conversation_messages_path(conversation), params: {
        message: { content: "/invite" }
      }
    end

    assert_redirected_to conversation_path(conversation)
    error_msg = Message.where(role: :system).last
    assert_includes error_msg.content, "Command error"
  end

  # ============================================================================
  # ADVISOR INVITATION FLOW
  # ============================================================================

  test "advisor invitation via controller action" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invite Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_difference("ConversationParticipant.count", 1) do
      post invite_advisor_conversation_path(conversation), params: {
        advisor_id: @advisor2.id
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert_includes conversation.advisors.reload, @advisor2
    assert flash[:notice].present?
  end

  test "advisor invitation fails for already invited advisor" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Duplicate Invite Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # Try to invite already-present advisor
    assert_no_difference("ConversationParticipant.count") do
      post invite_advisor_conversation_path(conversation), params: {
        advisor_id: @advisor1.id
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
  end

  # ============================================================================
  # CANCEL PENDING FLOW
  # ============================================================================

  test "cancel pending messages flow" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Cancel Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :consensus
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # Create pending messages
    3.times do |i|
      conversation.messages.create!(
        account: @account,
        sender: @advisor1,
        role: "system",
        content: "[Response #{i}] is thinking...",
        status: "pending"
      )
    end

    post cancel_pending_conversation_path(conversation)
    assert_redirected_to conversation_path(conversation)
    assert flash[:notice].present?

    conversation.messages.where(status: :pending).each do |msg|
      assert msg.cancelled?
    end
  end

  # ============================================================================
  # CONVERSATION APPROVAL/REJECTION FLOW
  # ============================================================================

  test "approve summary saves memory and creates conversation_summary" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Approval Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      status: :concluding
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post approve_summary_conversation_path(conversation), params: {
      key_decisions: "Decision 1",
      action_items: "Action 1",
      insights: "Insight 1",
      open_questions: "Question 1",
      raw_summary: "Full summary"
    }

    assert_redirected_to conversation_path(conversation)
    assert conversation.reload.resolved?
    assert conversation.memory.present?

    memory_data = conversation.memory_data
    assert_equal "Decision 1", memory_data["key_decisions"]
  end

  test "reject summary resets conversation to active" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Rejection Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      status: :concluding,
      scribe_initiated_count: 2
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post reject_summary_conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert conversation.reload.active?
    assert_equal 0, conversation.scribe_initiated_count
  end
end
