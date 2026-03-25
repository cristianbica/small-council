# frozen_string_literal: true

require "test_helper"

class ConversationSlashCommandsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
    @space = spaces(:one)
    @advisor1 = advisors(:one)
    @advisor2 = advisors(:two)
    @scribe = advisors(:"scribe-space-one")
    @memory = memories(:one)

    sign_in_as(@user)
    set_tenant(@account)
  end

  test "/advisors opens modal turbo frame" do
    conversation = create_conversation

    assert_no_enqueued_jobs only: AIRunnerJob do
      post conversation_messages_path(conversation),
           params: { message: { content: "/advisors" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes @response.body, "page-modal"
    assert_includes @response.body, @advisor1.name
  end

  test "/memories opens memories list modal" do
    conversation = create_conversation

    post conversation_messages_path(conversation),
         params: { message: { content: "/memories" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes @response.body, "page-modal"
    assert_includes @response.body, @memory.title
    assert_includes @response.body, @memory.id.to_s
  end

  test "/memory opens selected memory modal" do
    conversation = create_conversation

    post conversation_messages_path(conversation),
         params: { message: { content: "/memory #{@memory.id}" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes @response.body, "page-modal"
    assert_includes @response.body, @memory.title
  end

  test "/invite adds advisor and records info message" do
    conversation = create_conversation

    assert_no_enqueued_jobs only: AIRunnerJob do
      assert_difference ["conversation.conversation_participants.count", "conversation.messages.where(message_type: :info).count"], 1 do
        post conversation_messages_path(conversation),
             params: { message: { content: "/invite #{@advisor2.name}" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    info_message = conversation.messages.where(message_type: :info).order(:id).last
    assert_equal "#{@user.display_name} added #{@advisor2.name}", info_message.content
  end

  test "/kick removes advisor and records info message" do
    conversation = create_conversation
    conversation.conversation_participants.create!(advisor: @advisor2, role: "advisor", position: 1)

    assert_no_enqueued_jobs only: AIRunnerJob do
      assert_difference "conversation.conversation_participants.count", -1 do
        assert_difference "conversation.messages.where(message_type: :info).count", 1 do
          post conversation_messages_path(conversation),
               params: { message: { content: "/kick #{@advisor2.name}" } },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end
    end

    assert_response :success
    info_message = conversation.messages.where(message_type: :info).order(:id).last
    assert_equal "#{@user.display_name} removed #{@advisor2.name}", info_message.content
  end

  test "/attach creates memory attachment message included as user message" do
    conversation = create_conversation

    assert_no_enqueued_jobs only: AIRunnerJob do
      assert_difference "conversation.messages.where(message_type: :memory_attachment).count", 1 do
        post conversation_messages_path(conversation),
             params: { message: { content: "/attach #{@memory.id}" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    attachment = conversation.messages.where(message_type: :memory_attachment).order(:id).last
    assert_equal "user", attachment.role
    assert_equal @user, attachment.sender
    assert_equal @memory.id, attachment.metadata["memory_id"]
    assert_equal @memory.title, attachment.metadata["memory_title"]
  end

  test "command validation errors render inline drawer with 422 turbo response" do
    conversation = create_conversation

    post conversation_messages_path(conversation),
         params: { message: { content: "/attach abc" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :unprocessable_entity
    assert_includes @response.body, "Memory ID must be a number"
  end

  private

  def create_conversation
    conversation = @account.conversations.create!(
      title: "Command Test",
      user: @user,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor1, role: "advisor", position: 0)
    conversation.conversation_participants.create!(advisor: @scribe, role: "scribe", position: 99)
    conversation
  end
end
