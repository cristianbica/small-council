# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # List past conversations with pagination
      class ListConversationsTool < BaseTool
        def description
          "List past conversations in this space with pagination. Use to browse conversation history."
        end

        def parameters
          {
            type: "object",
            properties: {
              status: {
                type: "string",
                enum: Conversation.statuses.keys,
                description: "Filter by conversation status (optional)"
              },
              council_id: {
                type: "integer",
                description: "Filter by specific council (optional)"
              },
              limit: {
                type: "integer",
                description: "Maximum number of results to return (default: 10, max: 20)",
                minimum: 1,
                maximum: 20
              },
              offset: {
                type: "integer",
                description: "Number of results to skip (for pagination)",
                minimum: 0
              }
            },
            required: []
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          status = arguments[:status] || arguments["status"]
          council_id = arguments[:council_id] || arguments["council_id"]
          limit = arguments[:limit] || arguments["limit"]
          offset = arguments[:offset] || arguments["offset"]

          # Apply limit bounds
          limit = limit.to_i
          limit = 10 if limit < 1
          limit = 20 if limit > 20

          offset = offset.to_i
          offset = 0 if offset < 0

          space = context[:space]
          scope = space.conversations

          # Apply filters
          if status.present? && Conversation.statuses.key?(status.to_s)
            scope = scope.where(status: status)
          end

          if council_id.present?
            scope = scope.where(council_id: council_id)
          end

          total_count = scope.count
          conversations = scope.recent.limit(limit).offset(offset)

          {
            success: true,
            count: conversations.count,
            total_count: total_count,
            limit: limit,
            offset: offset,
            has_more: (offset + conversations.count) < total_count,
            conversations: conversations.map { |c| format_conversation(c) }
          }
        end

        private

        def format_conversation(conversation)
          {
            id: conversation.id,
            title: conversation.title,
            council: conversation.council&.name,
            status: conversation.status,
            rules_of_engagement: conversation.rules_of_engagement,
            message_count: conversation.messages.count,
            last_message_at: conversation.last_message_at&.strftime("%Y-%m-%d %H:%M"),
            created_at: conversation.created_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      end
    end
  end
end
