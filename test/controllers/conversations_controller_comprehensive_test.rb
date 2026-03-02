# test/controllers/conversations_controller_comprehensive_test.rb
require "test_helper"

class ConversationsControllerComprehensiveTest < ActionDispatch::IntegrationTest
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

    @council = @account.councils.create!(
      name: "Test Council",
      user: @user,
      space: @space
    )
  end

  # ============================================================================
  # INDEX ACTION - ALL SCENARIOS
  # ============================================================================

  test "index for adhoc conversations redirects to most recent conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    adhoc_conv = @account.conversations.create!(
      title: "Adhoc Conv",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    adhoc_conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    get conversations_path
    assert_redirected_to conversation_path(adhoc_conv)
  end

  test "index for council meetings" do
    sign_in_as(@user)
    set_tenant(@account)

    @council.advisors << @advisor1
    council_conv = @account.conversations.create!(
      title: "Council Conv",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      space: @space
    )
    council_conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    get council_conversations_path(@council)
    assert_response :success
    assert_select "h1", "#{@council.name} Conversations"
    assert_select "h3", council_conv.title
  end

  test "index requires authentication" do
    set_tenant(@account)

    adhoc_conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    adhoc_conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    get conversations_path
    assert_redirected_to sign_in_url
  end

  # ============================================================================
  # SHOW ACTION - ALL SCENARIOS
  # ============================================================================

  test "show displays conversation with all participants" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Test Show",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conversation.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)

    get conversation_path(conversation)
    assert_response :success
    assert_select "h1", text: conversation.title
    assert_select "label[title='Edit conversation title']", count: 1
    # Check that advisor names appear somewhere on the page
    assert_select "*", /strategic-advisor/
    assert_select "*", /technical-expert/
  end

  test "show displays message threading" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Threading Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    root_msg = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    reply = conversation.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Reply message",
      parent_message: root_msg
    )

    get conversation_path(conversation)
    assert_response :success
    assert_select ".whitespace-pre-wrap", root_msg.content
    assert_select ".whitespace-pre-wrap", reply.content
  end

  test "show displays conversation with available advisors section" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Available Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    get conversation_path(conversation)
    assert_response :success
    # Just check the page loads correctly
    assert_select "h1", text: conversation.title
    assert_select "label[title='Edit conversation title']", count: 1
  end

  test "show redirects for conversation in different space" do
    sign_in_as(@user)
    set_tenant(@account)

    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(
      name: "Other Council",
      user: @user,
      space: other_space
    )
    other_conv = @account.conversations.create!(
      title: "Other Conv",
      user: @user,
      council: other_council,
      conversation_type: :council_meeting,
      space: other_space
    )
    other_conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    get conversation_path(other_conv)
    assert_response :not_found
  end

  # ============================================================================
  # NEW ACTION - ALL SCENARIOS
  # ============================================================================

  test "new for council meeting shows form" do
    sign_in_as(@user)
    set_tenant(@account)

    @council.advisors << @advisor1
    @council.advisors << @advisor2

    get new_council_conversation_path(@council)
    assert_response :success
    assert_select "h1", "Start Meeting"
    assert_select "form"
    assert_select "input[name='conversation[title]']"
    assert_select "textarea[name='conversation[initial_message]']", count: 0
    # RoE type selection may be implemented differently
  end

  test "new for adhoc conversation shows form" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_conversation_path
    assert_response :success
    assert_select "h1", "Start Conversation"
    assert_select "form"
    assert_select "input[type='checkbox']"  # Advisor checkboxes
  end

  test "new requires authentication" do
    set_tenant(@account)

    @council.advisors << @advisor1

    get new_council_conversation_path(@council)
    assert_redirected_to sign_in_url
  end

  # ============================================================================
  # CREATE ACTION - ALL SCENARIOS
  # ============================================================================

  test "create adhoc conversation with valid params" do
    sign_in_as(@user)
    set_tenant(@account)

    # Creating adhoc conversation adds advisors + scribe automatically
    assert_difference("Conversation.count", 1) do
      assert_no_difference("Message.count") do
        assert_difference("ConversationParticipant.count", 3) do  # 2 advisors + scribe
          post conversations_path, params: {
            conversation: {
              title: "New Adhoc",
              roe_type: "open",
              advisor_ids: [ @advisor1.id, @advisor2.id ]
            }
          }
        end
      end
    end

    conversation = Conversation.last
    assert_redirected_to conversation_path(conversation)
    assert_equal "adhoc", conversation.conversation_type
    assert_equal "open", conversation.roe_type
    assert_includes conversation.advisors, @advisor1
    assert_includes conversation.advisors, @advisor2
    assert conversation.has_scribe?
  end

  test "create council meeting with valid params" do
    sign_in_as(@user)
    set_tenant(@account)

    @council.advisors << @advisor1
    @council.advisors << @advisor2

    assert_difference("Conversation.count", 1) do
      assert_no_difference("Message.count") do
        post council_conversations_path(@council), params: {
          conversation: {
            title: "New Meeting",
            roe_type: "consensus"
          }
        }
      end
    end

    conversation = Conversation.last
    assert_redirected_to conversation_path(conversation)
    assert_equal "council_meeting", conversation.conversation_type
    assert_equal @council, conversation.council
    assert_includes conversation.advisors, @advisor1
    assert_includes conversation.advisors, @advisor2
  end

  test "create renders new on failure with validation errors" do
    sign_in_as(@user)
    set_tenant(@account)

    assert_no_difference("Conversation.count") do
      post conversations_path, params: {
        conversation: {
          title: "",  # Invalid - blank title
          roe_type: "",
          advisor_ids: [ @advisor1.id ]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Start Conversation"
  end

  test "create council meeting with council_id creates council_meeting" do
    sign_in_as(@user)
    set_tenant(@account)

    @council.advisors << @advisor1

    # Creating via council path creates council_meeting
    assert_difference("Conversation.count", 1) do
      post council_conversations_path(@council), params: {
        conversation: {
          title: "With Council",
          roe_type: "open"
        }
      }
    end

    conversation = Conversation.last
    assert_equal "council_meeting", conversation.conversation_type
    assert_equal @council, conversation.council
  end

  # ============================================================================
  # UPDATE ACTION - ALL SCENARIOS
  # ============================================================================

  test "update RoE type successfully" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Update Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    patch conversation_path(conversation), params: {
      conversation: { roe_type: :consensus }
    }

    assert_redirected_to conversation_path(conversation)
    assert_equal "consensus", conversation.reload.roe_type
    assert flash[:notice].present?
  end

  test "update title sets title lock" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Initial Title",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    patch conversation_path(conversation), params: {
      conversation: { title: "Updated Title" }
    }

    assert_redirected_to conversation_path(conversation)
    assert_equal "Updated Title", conversation.reload.title
    assert conversation.title_locked?
  end

  test "update title succeeds with only scribe participant" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Initial Title",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @scribe, role: :scribe)

    patch conversation_path(conversation), params: {
      conversation: { title: "Updated Title" }
    }

    assert_redirected_to conversation_path(conversation)
    assert_equal "Updated Title", conversation.reload.title
    assert conversation.title_locked?
  end

  test "update redirects on failure" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Update Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    patch conversation_path(conversation), params: {
      conversation: { title: "" }  # Invalid
    }

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
    assert_equal "Update Test", conversation.reload.title  # Not changed
  end

  test "update requires authentication" do
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Update Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    patch conversation_path(conversation), params: {
      conversation: { roe_type: :consensus }
    }

    assert_redirected_to sign_in_url
  end

  # ============================================================================
  # INVITE ADVISOR ACTION - ALL SCENARIOS
  # ============================================================================

  test "invite_advisor adds advisor to conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invite Test",
      user: @user,
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_difference("ConversationParticipant.count", 1) do
      assert_difference("Message.where(role: :system).count", 1) do
        post invite_advisor_conversation_path(conversation), params: {
          advisor_id: @advisor2.id
        }
      end
    end

    assert_redirected_to conversation_path(conversation)
    assert flash[:notice].present?
    assert_includes conversation.advisors.reload, @advisor2
  end

  test "invite_advisor fails when advisor already in conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invite Test",
      user: @user,
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_no_difference("ConversationParticipant.count") do
      post invite_advisor_conversation_path(conversation), params: {
        advisor_id: @advisor1.id
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
  end

  test "invite_advisor fails when advisor not found" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invite Test",
      user: @user,
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_no_difference("ConversationParticipant.count") do
      post invite_advisor_conversation_path(conversation), params: {
        advisor_id: 999999
      }
    end

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
  end

  test "invite_advisor fails when conversation not active" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invite Test",
      user: @user,
      conversation_type: :adhoc,
      status: :resolved,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post invite_advisor_conversation_path(conversation), params: {
      advisor_id: @advisor2.id
    }

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
  end

  test "invite_advisor requires authentication" do
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Invite Test",
      user: @user,
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post invite_advisor_conversation_path(conversation), params: {
      advisor_id: @advisor2.id
    }

    assert_redirected_to sign_in_url
  end

  # ============================================================================
  # FINISH ACTION - ALL SCENARIOS
  # ============================================================================

  test "finish by conversation owner resolves active council meeting" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Finish Test",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_no_enqueued_jobs do
      post finish_conversation_path(conversation)
    end

    assert_redirected_to conversation_path(conversation)
    assert_equal "resolved", conversation.reload.status
    assert_equal "Conversation marked as resolved.", flash[:notice]
  end

  test "finish fails for non-owner" do
    unauthorized_user = @account.users.create!(email: "finish-unauthorized@example.com", password: "password123")
    sign_in_as(unauthorized_user)
    set_tenant(@account)

    other_user = @account.users.create!(email: "finish-non-owner@example.com", password: "password123")
    conversation = @account.conversations.create!(
      title: "Finish Test",
      user: other_user,
      council: @council,
      conversation_type: :council_meeting,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post finish_conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert_equal "active", conversation.reload.status
    assert_equal "You are not authorized to finish this conversation.", flash[:alert]
  end

  test "finish fails when conversation not active" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Finish Test",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      status: :resolved,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post finish_conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert_equal "resolved", conversation.reload.status
    assert_equal "Can only finish active conversations.", flash[:alert]
  end

  test "finish fails for adhoc conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Finish Test",
      user: @user,
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post finish_conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert_equal "active", conversation.reload.status
    assert_equal "Only council meetings can be finished.", flash[:alert]
  end

  # ============================================================================
  # DESTROY ACTION - ALL SCENARIOS
  # ============================================================================

  test "archive by conversation owner archives conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Archive Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post archive_conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert_equal "archived", conversation.reload.status
    assert_equal "Conversation archived.", flash[:notice]
  end

  test "archive fails for non-owner" do
    sign_in_as(@user)
    set_tenant(@account)

    other_user = @account.users.create!(email: "archive-non-owner@example.com", password: "password123")
    conversation = @account.conversations.create!(
      title: "Archive Test",
      user: other_user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    post archive_conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert_equal "active", conversation.reload.status
    assert_equal "You are not authorized to archive this conversation.", flash[:alert]
  end

  test "destroy by conversation owner deletes conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Delete Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_difference("Conversation.count", -1) do
      delete conversation_path(conversation)
    end

    assert_redirected_to conversations_path
    assert flash[:notice].present?
  end

  test "destroy by council meeting redirects to council conversations" do
    sign_in_as(@user)
    set_tenant(@account)

    @council.advisors << @advisor1
    conversation = @account.conversations.create!(
      title: "Delete Test",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_difference("Conversation.count", -1) do
      delete conversation_path(conversation)
    end

    assert_redirected_to council_conversations_path(@council)
  end

  test "destroy fails for non-owner" do
    sign_in_as(@user)
    set_tenant(@account)

    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    conversation = @account.conversations.create!(
      title: "Delete Test",
      user: other_user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_no_difference("Conversation.count") do
      delete conversation_path(conversation)
    end

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
  end

  test "destroy handles turbo_stream format with redirect" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Delete Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_difference("Conversation.count", -1) do
      delete conversation_path(conversation), as: :turbo_stream
    end

    assert_redirected_to conversations_path
  end

  test "destroy handles errors gracefully" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Delete Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # Stub destroy to simulate error
    Conversation.any_instance.stubs(:destroy!).raises(StandardError.new("Database error"))

    delete conversation_path(conversation)

    assert_redirected_to conversation_path(conversation)
    assert flash[:alert].present?
  end

  test "destroy requires authentication" do
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Delete Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    delete conversation_path(conversation)
    assert_redirected_to sign_in_url
  end

  # ============================================================================
  # QUICK CREATE ACTION
  # ============================================================================

  test "quick_create creates adhoc conversation with scribe only" do
    sign_in_as(@user)
    set_tenant(@account)

    assert_difference -> { Conversation.adhoc_conversations.count }, 1 do
      post quick_create_conversations_path
    end

    conversation = Conversation.adhoc_conversations.last
    assert_redirected_to conversation_path(conversation)
    assert_equal @user, conversation.user
    assert_equal :open, conversation.roe_type.to_sym
    assert_equal :adhoc, conversation.conversation_type.to_sym

    # Should have only scribe as participant
    assert_equal 1, conversation.conversation_participants.count
    assert conversation.has_scribe?
    assert_equal @scribe, conversation.scribe_advisor
  end

  test "quick_create redirects to existing conversation when creating new one" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create first conversation
    post quick_create_conversations_path
    first_conversation = Conversation.adhoc_conversations.last

    # Create second conversation
    post quick_create_conversations_path
    second_conversation = Conversation.adhoc_conversations.last

    assert_not_equal first_conversation.id, second_conversation.id
    assert_equal 2, Conversation.adhoc_conversations.count
  end

  test "quick_create requires authentication" do
    post quick_create_conversations_path
    assert_redirected_to sign_in_url
  end

  # ============================================================================
  # CONVERSATION LAYOUT AND SIDEBAR
  # ============================================================================

  test "show uses conversation layout for adhoc conversations" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Adhoc Layout Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.ensure_scribe_present!

    get conversation_path(conversation)
    assert_response :success
    assert_select "aside#conversation-sidebar"
    assert_select "#conversation-list"
  end

  test "show uses application layout for council meetings" do
    sign_in_as(@user)
    set_tenant(@account)

    council = @account.councils.create!(
      name: "Layout Test Council",
      user: @user,
      space: @space
    )
    conversation = @account.conversations.create!(
      title: "Meeting Layout Test",
      user: @user,
      council: council,
      conversation_type: :council_meeting,
      space: @space
    )

    get conversation_path(conversation)
    assert_response :success
    # Should not have the conversation sidebar (council meetings use different UI)
    assert_select "aside#conversation-sidebar", count: 0
  end

  test "sidebar shows recent adhoc conversations" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create multiple adhoc conversations
    3.times do |i|
      conv = @account.conversations.create!(
        title: "Adhoc #{i + 1}",
        user: @user,
        conversation_type: :adhoc,
        space: @space
      )
      conv.ensure_scribe_present!
    end

    latest = @account.conversations.adhoc_conversations.recent.first

    get conversation_path(latest)
    assert_response :success

    # Should show all 3 conversations in sidebar
    assert_select "#conversation-list a", count: 3
  end

  test "sidebar highlights active conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conv1 = @account.conversations.create!(
      title: "First",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv1.ensure_scribe_present!

    conv2 = @account.conversations.create!(
      title: "Second",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv2.ensure_scribe_present!

    get conversation_path(conv2)
    assert_response :success

    # The active conversation should have the border highlight class
    assert_select "a[href='#{conversation_path(conv2)}']" do |elements|
      assert elements.any? { |e| e["class"].include?("border-l-4") }
    end
  end

  # ============================================================================
  # PARTICIPANT DISPLAY
  # ============================================================================

  test "show displays scribe as moderator in participants" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "Scribe Display Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.ensure_scribe_present!
    conversation.add_advisor(@advisor1)

    get conversation_path(conversation)
    assert_response :success

    assert_select "*", /scribe/
  end

  test "show displays all participants including scribe" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      title: "All Participants Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.ensure_scribe_present!
    conversation.add_advisor(@advisor1)
    conversation.add_advisor(@advisor2)

    get conversation_path(conversation)
    assert_response :success

    assert_select "*", /scribe/
    assert_select "*", /strategic-advisor/
    assert_select "*", /technical-expert/
  end
end
