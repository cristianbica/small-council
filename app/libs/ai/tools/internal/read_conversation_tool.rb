# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Read conversation messages by conversation ID
      class ReadConversationTool < BaseTool
        def description
          "Read the messages from a specific conversation. Use this to review past discussions."
        end

        def parameters
          {
            type: "object",
            properties: {
              conversation_id: {
                type: "integer",
                description: "ID of the conversation to read (required)"
              },
              limit: {
                type: "integer",
                description: "Maximum number of messages to return (default: 50, max: 100)",
                minimum: 1,
                maximum: 100
              },
              offset: {
                type: "integer",
                description: "Number of messages to skip from the beginning",
                minimum: 0
              }
            },
            required: [ :conversation_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          conversation_id = arguments[:conversation_id] || arguments["conversation_id"]
          limit = arguments[:limit] || arguments["limit"]
          offset = arguments[:offset] || arguments["offset"]

          if conversation_id.blank?
            return { success: false, error: "conversation_id is required" }
          end

          # Apply limit bounds
          limit = limit.to_i
          limit = 50 if limit < 1
          limit = 100 if limit > 100

          offset = offset.to_i
          offset = 0 if offset < 0

          space = context[:space]
          conversation = space.conversations.find_by(id: conversation_id)

          unless conversation
            return {
              success: false,
              error: "Conversation not found with ID: #{conversation_id}"
            }
          end

          total_count = conversation.messages.count
          messages = conversation.messages.chronological.limit(limit).offset(offset)

          {
            success: true,
            conversation_id: conversation.id,
            conversation_title: conversation.title,
            council: conversation.council&.name,
            count: messages.count,
            total_count: total_count,
            limit: limit,
            offset: offset,
            has_more: (offset + messages.count) < total_count,
            messages: messages.map { |m| format_message(m) }
          }
        end

        private

        def format_message(message)
          {
            id: message.id,
            sender: message.sender.try(:name) || message.sender.try(:email) || "Unknown",
            sender_type: message.sender_type,
            role: message.role,
            content: message.content,
            status: message.status,
            created_at: message.created_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      end
    end
  end
end
