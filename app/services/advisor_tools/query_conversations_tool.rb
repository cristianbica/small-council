module AdvisorTools
  class QueryConversationsTool < AdvisorTool
    def tool_name
      "query_conversations"
    end

    def tool_description
      "Search for conversations in this space by topic or keyword. Returns a list of matching conversations with their IDs, titles, and summaries. Use this when users ask about previous discussions or want to find conversations about specific topics."
    end

    def tool_parameters
      {
        query: {
          type: "string",
          required: true,
          description: "Search term or topic to find conversations about (e.g., 'API authentication', 'deployment', 'architecture decisions')"
        },
        limit: {
          type: "integer",
          required: false,
          description: "Maximum number of conversations to return (default: 5, max: 10)"
        },
        status: {
          type: "string",
          required: false,
          enum: [ "active", "concluding", "resolved", "archived" ],
          description: "Filter by conversation status (default: any)"
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

      query = params["query"].to_s.downcase.strip
      if query.blank?
        return {
          success: false,
          message: "Query cannot be blank."
        }
      end

      limit = [ [ params["limit"].to_i, 10 ].min, 1 ].max
      limit = 5 if limit < 1

      status = params["status"]

      scope = context.space.conversations
      scope = scope.where(status: status) if status.present?

      # Search in title, summary (memory), and messages
      conversations = scope.select do |conv|
        searchable_text = [
          conv.title,
          conv.memory,
          conv.messages.map(&:content)
        ].compact.join(" ").downcase

        searchable_text.include?(query)
      end.first(limit)

      if conversations.empty?
        return {
          success: true,
          message: "No conversations found matching '#{params["query"]}'",
          data: {
            query: params["query"],
            count: 0,
            conversations: []
          }
        }
      end

      {
        success: true,
        message: "Found #{conversations.size} conversation(s) matching '#{params["query"]}'",
        data: {
          query: params["query"],
          count: conversations.size,
          conversations: conversations.map do |conv|
            {
              id: conv.id,
              title: conv.title,
              status: conv.status,
              council_name: conv.council&.name,
              message_count: conv.messages.count,
              summary_preview: conv.memory&.truncate(200),
              updated_at: conv.updated_at.strftime("%Y-%m-%d %H:%M")
            }
          end
        }
      }
    rescue => e
      Rails.logger.error "[AdvisorTools::QueryConversationsTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      {
        success: false,
        message: "Failed to query conversations: #{e.message}"
      }
    end

    def read_only?
      true
    end
  end
end
