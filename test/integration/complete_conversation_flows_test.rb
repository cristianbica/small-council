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

    # Use the auto-created scribe from the space
    @scribe = @space.scribe_advisor

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
      assert_no_difference("Message.count") do
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
    assert_enqueued_jobs 1, only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@strategic-advisor what do you think?" }
      }
    end
    assert_redirected_to conversation_path(conversation)

    # Step 4: Post message without mention (no responses in Open RoE)
    assert_no_enqueued_jobs only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "What does everyone think?" }
      }
    end
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
    assert_enqueued_jobs 1, only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@strategic-advisor What do you all think?" }
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
    assert_enqueued_jobs 1, only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@technical-expert Brainstorm ideas for our product" }
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
      assert_no_difference("Message.count") do
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
    assert_enqueued_jobs 1, only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@strategic-advisor What are our priorities?" }
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
  # @ALL MENTION EXPANSION FLOW
  # ============================================================================

  test "@all mention expands to all advisors in Open RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "@all Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )

    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # @all includes all advisors (2 advisors)
    assert_enqueued_jobs 1, only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@all what are your thoughts?" }
      }
    end
  end

  test "@everyone mention expands to all advisors in Open RoE" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "@everyone Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # @everyone includes all advisors (2 advisors)
    assert_enqueued_jobs 1, only: AIRunnerJob do
      post conversation_messages_path(conversation), params: {
        message: { content: "@everyone please respond" }
      }
    end
  end

  # ============================================================================
  # COMMAND EXECUTION FLOW
  # ============================================================================

  test "slash invite text does not auto-invite advisors" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Command Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # Slash commands are no longer parsed in the runtime path.
    assert_no_difference("ConversationParticipant.count") do
      post conversation_messages_path(conversation), params: {
        message: { content: "/invite @technical-expert" }
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert_not_includes conversation.advisors.reload, @advisor2
  end

  test "slash command-like text is stored as a normal user message" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invalid Command Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_difference("Message.where(role: :user).count", 1) do
      post conversation_messages_path(conversation), params: {
        message: { content: "/invite" }
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert_equal "/invite", Message.where(role: :user).last.content
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
      roe_type: :open,
      space: @space
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
      roe_type: :open,
      space: @space
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
end
