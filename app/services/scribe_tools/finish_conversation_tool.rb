class ScribeTools::FinishConversationTool < ScribeTool
  def tool_name
    "finish_conversation"
  end

  def tool_description
    "Conclude the current conversation and initiate the summary generation process. Use this when the conversation has reached a natural conclusion, key decisions have been made, or the user explicitly asks to end the discussion."
  end

  def tool_parameters
    {
      conversation_id: {
        type: "string",
        required: true,
        description: "The ID of the conversation to finish"
      },
      reason: {
        type: "string",
        required: false,
        description: "Optional reason for finishing the conversation"
      }
    }
  end

  def execute(params, context)
    conversation = context.conversation

    # Validate conversation_id matches current context
    if params["conversation_id"].to_s != conversation&.id.to_s
      return {
        success: false,
        message: "Invalid conversation_id. Can only finish the current conversation."
      }
    end

    unless conversation&.active?
      return {
        success: false,
        message: "Conversation is not in active state. Current status: #{conversation&.status}"
      }
    end

    # Initiate conclusion process
    lifecycle = ConversationLifecycle.new(conversation)
    lifecycle.begin_conclusion_process

    # Broadcast notification
    context.broadcast_message(
      "🔚 The Scribe has initiated the conclusion process for this conversation. " \
      "A summary will be generated for your review.#{params["reason"] ? " Reason: #{params["reason"]}" : ""}"
    )

    {
      success: true,
      message: "Conversation conclusion initiated. Summary generation in progress.",
      data: {
        conversation_id: conversation.id,
        new_status: "concluding"
      }
    }
  rescue => e
    Rails.logger.error "[FinishConversationTool] Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")

    {
      success: false,
      message: "Failed to finish conversation: #{e.message}"
    }
  end
end
