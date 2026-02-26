module RubyLLMTools
  class QueryConversationsTool < RubyLLM::Tool
    description "Search for past conversations by topic or keyword"

    param :query,
      desc: "Topic or keyword to search for in conversations",
      type: :string,
      required: true

    param :limit,
      desc: "Maximum number of conversations to return (default: 5)",
      type: :integer,
      required: false

    def execute(query:, limit: 5)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      limit = [ limit.to_i, 10 ].min
      query_down = query.downcase

      conversations = context[:space].conversations.recent.limit(20).select do |conv|
        searchable = [
          conv.title,
          conv.memory,
          conv.messages.limit(10).map(&:content)
        ].join(" ").downcase
        searchable.include?(query_down)
      end.first(limit)

      if conversations.empty?
        return {
          success: true,
          message: "No conversations found matching '#{query}'",
          conversations: []
        }
      end

      {
        success: true,
        message: "Found #{conversations.size} conversation(s) about '#{query}'",
        conversations: conversations.map do |c|
          {
            id: c.id,
            title: c.title,
            status: c.status,
            message_count: c.messages.count,
            summary: c.memory&.truncate(200),
            updated_at: c.updated_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      }
    end
  end
end
