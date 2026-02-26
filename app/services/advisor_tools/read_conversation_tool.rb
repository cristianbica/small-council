module AdvisorTools
  class ReadConversationTool < AdvisorTool
    def tool_name
      "read_conversation"
    end

    def tool_description
      "Read all messages from a specific conversation by ID. Returns the conversation title, status, summary, and all messages with sender information. Use this after finding a conversation with query_conversations to get the full details."
    end

    def tool_parameters
      {
        conversation_id: {
          type: "string",
          required: true,
          description: "The ID of the conversation to read (e.g., '123', 'abc-456')"
        }
      }
    end

    def execute(params, context)
      unless context.space
        return {
          success: false,
          message: "No space context available."
        }
      end

      conversation_id = params["conversation_id"].to_s.strip
      if conversation_id.blank?
        return {
          success: false,
          message: "Conversation ID cannot be blank."
        }
      end

      conversation = context.space.conversations.find_by(id: conversation_id)

      unless conversation
        return {
          success: false,
          message: "Conversation #{conversation_id} not found in this space"
        }
      end

      messages = conversation.messages.chronological.map do |msg|
        sender_name = if msg.sender.respond_to?(:name)
          msg.sender.name
        elsif msg.sender.respond_to?(:title)
          msg.sender.title
        else
          msg.sender_type
        end

        {
          id: msg.id,
          sender: sender_name,
          role: msg.role,
          content: msg.content,
          created_at: msg.created_at.strftime("%Y-%m-%d %H:%M")
        }
      end

      {
        success: true,
        message: "Retrieved #{messages.size} messages from conversation ##{conversation.id}",
        data: {
          conversation: {
            id: conversation.id,
            title: conversation.title,
            status: conversation.status,
            council_name: conversation.council&.name,
            summary: conversation.memory,
            updated_at: conversation.updated_at.strftime("%Y-%m-%d %H:%M")
          },
          messages: messages
        }
      }
    rescue => e
      Rails.logger.error "[AdvisorTools::ReadConversationTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      {
        success: false,
        message: "Failed to read conversation: #{e.message}"
      }
    end

    def read_only?
      true
    end
  end
end
