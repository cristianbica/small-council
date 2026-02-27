module RubyLLMTools
  class AdvisorQueryConversationsTool < RubyLLM::Tool
    description "Search for conversations in this space by topic or keyword. Returns a list of matching conversations with their IDs, titles, and summaries. Use this when users ask about previous discussions or want to find conversations about specific topics."

    param :query,
      desc: "Search term or topic to find conversations about (e.g., 'API authentication', 'deployment', 'architecture decisions')",
      type: :string,
      required: true

    param :limit,
      desc: "Maximum number of conversations to return (default: 5, max: 10)",
      type: :integer,
      required: false

    param :status,
      desc: "Filter by conversation status (default: any)",
      type: :string,
      required: false

    def execute(query:, limit: 5, status: nil)
      context = Thread.current[:advisor_tool_context]
      return { error: "No context available" } unless context

      tool = AdvisorTools::QueryConversationsTool.new
      params = {
        "query" => query,
        "limit" => limit,
        "status" => status
      }

      result = tool.execute(params, context)

      if result[:success]
        { success: true, message: result[:message], data: result[:data] }
      else
        { error: result[:message] }
      end
    rescue => e
      Rails.logger.error "[AdvisorQueryConversationsTool] Error: #{e.message}"
      { error: "Failed to query conversations: #{e.message}" }
    end
  end
end
