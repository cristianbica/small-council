require "test_helper"
require "securerandom"

class ConversationParticipantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @owner = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    set_tenant(@account)

    provider = @account.providers.create!(
      name: "participant-provider-#{SecureRandom.hex(4)}",
      provider_type: "openai",
      api_key: "test-key"
    )
    @model_one = provider.llm_models.create!(
      account: @account,
      name: "Participant Model One",
      identifier: "participant-model-one"
    )
    @model_two = provider.llm_models.create!(
      account: @account,
      name: "Participant Model Two",
      identifier: "participant-model-two"
    )

    @conversation = @account.conversations.create!(
      title: "Participant Config Conversation",
      user: @owner,
      conversation_type: :adhoc,
      roe_type: :open,
      space: @space
    )

    @advisor = @account.advisors.create!(
      name: "participant-advisor-#{SecureRandom.hex(4)}",
      system_prompt: "You are a participant test advisor.",
      space: @space,
      is_scribe: false,
      llm_model: @model_one
    )

    @participant = @conversation.conversation_participants.create!(
      advisor: @advisor,
      role: :advisor,
      position: 1
    )
  end

  test "edit redirects to sign in when unauthenticated" do
    get edit_conversation_conversation_participant_url(@conversation, @participant)

    assert_redirected_to sign_in_url
  end

  test "edit renders participant config modal when authorized" do
    sign_in_as(@owner)

    get edit_conversation_conversation_participant_url(@conversation, @participant),
      headers: { "Turbo-Frame" => "page-modal" }

    assert_response :success
    assert_includes @response.body, "Configure #{@advisor.name}"
    assert_includes @response.body, "conversation_participant[tools]"
  end

  test "edit redirects when user is not allowed to manage conversation" do
    other_user = @account.users.create!(email: "participant-edit-other-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in_as(other_user)

    get edit_conversation_conversation_participant_url(@conversation, @participant)

    assert_redirected_to conversation_url(@conversation)
    assert_equal "You are not authorized to update advisor configuration for this conversation.", flash[:alert]
  end

  test "edit returns not found when conversation is missing" do
    sign_in_as(@owner)

    get edit_conversation_conversation_participant_url(id: @participant.id, conversation_id: 999_999)

    assert_response :not_found
  end

  test "edit returns not found when participant is missing" do
    sign_in_as(@owner)

    get edit_conversation_conversation_participant_url(@conversation, 999_999)

    assert_response :not_found
  end

  test "update persists nested tools and llm model" do
    sign_in_as(@owner)

    patch conversation_conversation_participant_url(@conversation, @participant), params: {
      conversation_participant: {
        llm_model_id: @model_two.id,
        tools: {
          "0" => { ref: "memories/create", policy: "deny" },
          "1" => { ref: "internet/browse_web", policy: "allow" }
        }
      }
    }

    assert_redirected_to conversation_url(@conversation)

    @participant.reload
    assert_equal @model_two.id, @participant.llm_model_id
    tools_by_ref = @participant.tools.index_by { |entry| entry["ref"] }
    assert_equal "deny", tools_by_ref["memories/create"]["policy"]
    assert_equal "allow", tools_by_ref["internet/browse_web"]["policy"]
  end

  test "update responds with turbo stream for turbo requests" do
    sign_in_as(@owner)

    patch conversation_conversation_participant_url(@conversation, @participant),
      params: {
        conversation_participant: {
          llm_model_id: @model_two.id,
          tools: {
            "0" => { ref: "internet/browse_web", policy: "allow" }
          }
        }
      },
      as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "conversation-participants"
  end

  test "update with invalid llm model id clears participant llm model" do
    sign_in_as(@owner)
    @participant.update!(llm_model: @model_one)

    patch conversation_conversation_participant_url(@conversation, @participant), params: {
      conversation_participant: {
        llm_model_id: "999999",
        tools: {
          "0" => { ref: "internet/browse_web", policy: "allow" }
        }
      }
    }

    assert_redirected_to conversation_url(@conversation)
    assert_nil @participant.reload.llm_model_id
  end

  test "update works when tools param is omitted" do
    sign_in_as(@owner)

    patch conversation_conversation_participant_url(@conversation, @participant), params: {
      conversation_participant: {
        llm_model_id: @model_two.id
      }
    }

    assert_redirected_to conversation_url(@conversation)
    assert_equal @model_two.id, @participant.reload.llm_model_id
  end

  test "update works when llm_model_id is omitted" do
    sign_in_as(@owner)
    @participant.update!(llm_model: @model_one)

    patch conversation_conversation_participant_url(@conversation, @participant), params: {
      conversation_participant: {
        tools: {
          "0" => { ref: "internet/browse_web", policy: "allow" }
        }
      }
    }

    assert_redirected_to conversation_url(@conversation)
    assert_equal @model_one.id, @participant.reload.llm_model_id
  end

  test "update renders unprocessable entity when update fails for html" do
    sign_in_as(@owner)
    ConversationParticipant.any_instance.stubs(:update).returns(false)

    patch conversation_conversation_participant_url(@conversation, @participant), params: {
      conversation_participant: {
        llm_model_id: @model_two.id,
        tools: {
          "0" => { ref: "internet/browse_web", policy: "allow" }
        }
      }
    }

    assert_response :unprocessable_entity
  end

  test "update renders unprocessable entity turbo stream when update fails" do
    sign_in_as(@owner)
    ConversationParticipant.any_instance.stubs(:update).returns(false)

    patch conversation_conversation_participant_url(@conversation, @participant),
      params: {
        conversation_participant: {
          llm_model_id: @model_two.id,
          tools: {
            "0" => { ref: "internet/browse_web", policy: "allow" }
          }
        }
      },
      as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes @response.body, "turbo-frame"
  end

  test "update redirects when user is not allowed to manage conversation" do
    other_user = @account.users.create!(email: "participant-other-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in_as(other_user)

    patch conversation_conversation_participant_url(@conversation, @participant), params: {
      conversation_participant: {
        llm_model_id: @model_two.id,
        tools: {
          "0" => { ref: "internet/browse_web", policy: "allow" }
        }
      }
    }

    assert_redirected_to conversation_url(@conversation)
    assert_equal "You are not authorized to update advisor configuration for this conversation.", flash[:alert]
    assert_not_equal @model_two.id, @participant.reload.llm_model_id
  end
end
