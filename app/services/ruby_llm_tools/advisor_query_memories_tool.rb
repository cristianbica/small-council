module RubyLLMTools
  class AdvisorQueryMemoriesTool < RubyLLM::Tool
    description "Search and retrieve memories from the space beyond the auto-fed summary. Use this when you need additional context, previous decisions, or specific knowledge to inform your response. Returns matching memories with title, type, and a preview of content. Note: The primary summary is automatically included in your context - use this tool for specific queries."

    param :query,
      desc: "Search terms to find relevant memories (e.g., 'API decisions', 'deployment process', 'database choice')",
      type: :string,
      required: true

    param :memory_type,
      desc: "Optional: Filter by memory type. If not specified, searches all types.",
      type: :string,
      required: false

    param :limit,
      desc: "Maximum number of memories to return (1-10)",
      type: :integer,
      required: false

    def execute(query:, memory_type: nil, limit: 5)
      context = Thread.current[:advisor_tool_context]
      return { error: "No context available" } unless context

      tool = AdvisorTools::QueryMemoriesTool.new
      params = {
        "query" => query,
        "memory_type" => memory_type,
        "limit" => limit
      }

      result = tool.execute(params, context)

      if result[:success]
        { success: true, message: result[:message], data: result[:data] }
      else
        { error: result[:message] }
      end
    rescue => e
      Rails.logger.error "[AdvisorQueryMemoriesTool] Error: #{e.message}"
      { error: "Failed to query memories: #{e.message}" }
    end
  end
end
