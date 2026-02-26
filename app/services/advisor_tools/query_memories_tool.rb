class AdvisorTools::QueryMemoriesTool < AdvisorTool
  def tool_name
    "query_memories"
  end

  def tool_description
    "Search and retrieve memories from the space beyond the auto-fed summary. Use this when you need additional context, previous decisions, or specific knowledge to inform your response. Returns matching memories with title, type, and a preview of content. Note: The primary summary is automatically included in your context - use this tool for specific queries."
  end

  def tool_parameters
    {
      query: {
        type: "string",
        required: true,
        description: "Search terms to find relevant memories (e.g., 'API decisions', 'deployment process', 'database choice')"
      },
      memory_type: {
        type: "string",
        required: false,
        enum: %w[conversation_summary conversation_notes knowledge summary],
        description: "Optional: Filter by memory type. If not specified, searches all types."
      },
      limit: {
        type: "integer",
        required: false,
        default: 5,
        description: "Maximum number of memories to return (1-10)"
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

    query = params["query"].to_s.strip
    if query.blank?
      return {
        success: false,
        message: "Query cannot be blank."
      }
    end

    limit = [ params["limit"].to_i, 10 ].min
    limit = 5 if limit < 1

    # Execute query
    memories = context.query_memories(
      query: query,
      memory_type: params["memory_type"],
      limit: limit
    )

    if memories.any?
      memory_list = memories.map do |memory|
        {
          id: memory.id,
          title: memory.title,
          type: memory.memory_type,
          content_preview: memory.content_preview(length: 400),
          created_at: memory.created_at.iso8601,
          source: memory.source_display
        }
      end

      type_filter = params["memory_type"] ? " [#{params["memory_type"]} only]" : ""

      {
        success: true,
        message: "Found #{memories.count} relevant memory/ies for '#{query}'#{type_filter}.",
        data: {
          query: query,
          count: memories.count,
          memories: memory_list
        }
      }
    else
      {
        success: true,
        message: "No memories found matching '#{query}'. The auto-fed summary should provide general context.",
        data: {
          query: query,
          count: 0,
          memories: []
        }
      }
    end
  rescue => e
    Rails.logger.error "[AdvisorTools::QueryMemoriesTool] Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")

    {
      success: false,
      message: "Failed to query memories: #{e.message}"
    }
  end

  # This tool is read-only
  def read_only?
    true
  end
end
