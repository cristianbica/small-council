class ScribeTools::CreateMemoryTool < ScribeTool
  def tool_name
    "create_memory"
  end

  def tool_description
    "Create a new memory entry in the space. Use this to save important decisions, insights, knowledge, or notes from the conversation. Memories can be of type: summary (space overview), conversation_summary (this conversation's takeaways), conversation_notes (detailed discussion notes), or knowledge (standalone facts)."
  end

  def tool_parameters
    {
      title: {
        type: "string",
        required: true,
        description: "Clear, descriptive title for this memory"
      },
      content: {
        type: "string",
        required: true,
        description: "The full content of the memory"
      },
      memory_type: {
        type: "string",
        required: true,
        enum: %w[summary conversation_summary conversation_notes knowledge],
        description: "Type of memory: summary (auto-fed to AI), conversation_summary, conversation_notes, or knowledge"
      },
      status: {
        type: "string",
        required: false,
        enum: %w[active draft],
        default: "active",
        description: "Status of the memory (active or draft)"
      }
    }
  end

  def execute(params, context)
    unless context.space
      return {
        success: false,
        message: "No space available. Cannot create memory."
      }
    end

    # Validate memory type
    unless Memory::MEMORY_TYPES.include?(params["memory_type"])
      return {
        success: false,
        message: "Invalid memory_type. Must be one of: #{Memory::MEMORY_TYPES.join(', ')}"
      }
    end

    # Create the memory
    memory = context.create_memory(
      title: params["title"],
      content: params["content"],
      memory_type: params["memory_type"],
      status: params["status"] || "active"
    )

    # Build informative message based on type
    type_explanation = case memory.memory_type
    when "summary"
      " This summary will be automatically included in AI agent context."
    when "conversation_summary"
      " This captures the key takeaways from this conversation."
    when "conversation_notes"
      " This preserves detailed notes from the discussion."
    when "knowledge"
      " This is now available for future queries."
    end

    {
      success: true,
      message: "Memory '#{memory.title}' created successfully.#{type_explanation}",
      data: {
        memory_id: memory.id,
        memory_type: memory.memory_type,
        title: memory.title
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    {
      success: false,
      message: "Failed to create memory: #{e.message}"
    }
  rescue => e
    Rails.logger.error "[CreateMemoryTool] Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")

    {
      success: false,
      message: "Failed to create memory: #{e.message}"
    }
  end
end
