class ScribeTools::QueryMemoriesTool < ScribeTool
  def tool_name
    "query_memories"
  end

  def tool_description
    "Search and retrieve memories from the space. Use this to find relevant context, previous decisions, or knowledge that can inform the current conversation. Returns matching memories with title, type, and a preview of content."
  end

  def tool_parameters
    {
      query: {
        type: "string",
        required: true,
        description: "Search terms to find relevant memories"
      },
      memory_type: {
        type: "string",
        required: false,
        enum: %w[summary conversation_summary conversation_notes knowledge],
        description: "Optional: Filter by memory type"
      },
      limit: {
        type: "integer",
        required: false,
        default: 5,
        description: "Maximum number of memories to return (1-20)"
      }
    }
  end

  def execute(params, context)
    unless context.space
      return {
        success: false,
        message: "No space available. Cannot query memories."
      }
    end

    query = params["query"].to_s.strip
    if query.blank?
      return {
        success: false,
        message: "Query cannot be blank."
      }
    end

    limit = [ params["limit"].to_i, 20 ].min
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
          content_preview: memory.content_preview(length: 500),
          created_at: memory.created_at.iso8601,
          source: memory.source_display
        }
      end

      type_note = params["memory_type"] ? " (filtered to #{params["memory_type"]} type)" : ""

      {
        success: true,
        message: "Found #{memories.count} memory/ies matching '#{query}'#{type_note}.",
        data: {
          query: query,
          count: memories.count,
          memories: memory_list
        }
      }
    else
      available_types = context.space.memories.active.distinct.pluck(:memory_type)

      {
        success: true,
        message: "No memories found matching '#{query}'. " \
          "Available memory types in this space: #{available_types.join(', ')}",
        data: {
          query: query,
          count: 0,
          memories: [],
          available_types: available_types
        }
      }
    end
  rescue => e
    Rails.logger.error "[QueryMemoriesTool] Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")

    {
      success: false,
      message: "Failed to query memories: #{e.message}"
    }
  end
end
