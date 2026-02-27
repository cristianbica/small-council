# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Search conversations by title or content
      class QueryConversationsTool < BaseTool
        def description
          "Search conversations by title or message content. Use this to find specific past discussions."
        end

        def parameters
          {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search term to find in conversation titles or messages (required)"
              },
              status: {
                type: "string",
                enum: Conversation.statuses.keys,
                description: "Filter by conversation status (optional)"
              },
              limit: {
                type: "integer",
                description: "Maximum number of results to return (default: 5, max: 10)",
                minimum: 1,
                maximum: 10
              }
            },
            required: [ :query ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          query = arguments[:query] || arguments["query"]
          status = arguments[:status] || arguments["status"]
          limit = arguments[:limit] || arguments["limit"]

          if query.blank?
            return {
              success: false,
              error: "Query parameter is required",
              conversations: []
            }
          end

          # Apply limit bounds
          limit = limit.to_i
          limit = 5 if limit < 1
          limit = 10 if limit > 10

          space = context[:space]

          # Start with conversations scope
          scope = space.conversations

          # Apply status filter if provided
          if status.present? && Conversation.statuses.key?(status.to_s)
            scope = scope.where(status: status)
          end

          # Search in title
          title_matches = scope.where("title ILIKE ?", "%#{query}%")

          # Search in message content
          message_matches = scope.joins(:messages)
                                 .where("messages.content ILIKE ?", "%#{query}%")
                                 .distinct

          # Combine results
          conversation_ids = (title_matches.pluck(:id) + message_matches.pluck(:id)).uniq
          conversations = space.conversations.where(id: conversation_ids).recent.limit(limit)

          if conversations.empty?
            return {
              success: true,
              message: "No conversations found matching '#{query}'",
              query: query,
              count: 0,
              conversations: []
            }
          end

          {
            success: true,
            message: "Found #{conversations.size} conversation(s) matching '#{query}'",
            query: query,
            limit: limit,
            count: conversations.size,
            conversations: conversations.map { |c| format_conversation(c) }
          }
        end

        private

        def format_conversation(conversation)
          last_message = conversation.messages.last
          {
            id: conversation.id,
            title: conversation.title,
            council: conversation.council&.name,
            status: conversation.status,
            message_count: conversation.messages.count,
            last_message_at: conversation.last_message_at&.strftime("%Y-%m-%d %H:%M"),
            preview: last_message&.content&.truncate(100) || "No messages"
          }
        end
      end
    end
  end
end
