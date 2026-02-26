module RubyLLMTools
  class UpdateMemoryTool < RubyLLM::Tool
    description "Updates an existing memory entry in the space. Use this to correct, expand, or modify existing memories."

    param :memory_id,
      desc: "The ID of the memory to update (required)",
      type: :integer

    param :title,
      desc: "The new title for the memory (optional - keeps existing if not provided)",
      type: :string

    param :content,
      desc: "The new content/body for the memory in markdown format (optional - keeps existing if not provided)",
      type: :string

    param :memory_type,
      desc: "New type of memory: summary, knowledge, conversation_summary, or conversation_notes (optional - keeps existing if not provided)",
      type: :string

    def execute(memory_id: nil, title: nil, content: nil, memory_type: nil)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      if memory_id.blank?
        return { error: "Memory ID is required" }
      end

      memory = context[:space].memories.active.find_by(id: memory_id)

      unless memory
        return {
          error: "Memory ##{memory_id} not found in this space",
          hint: "Use query_memories to find the correct memory ID"
        }
      end

      # Track what was updated
      updates = []

      if title.present? && title != memory.title
        memory.title = title
        updates << "title"
      end

      if content.present? && content != memory.content
        memory.content = content
        updates << "content"
      end

      if memory_type.present? && valid_memory_type(memory_type) != memory.memory_type
        memory.memory_type = valid_memory_type(memory_type)
        updates << "type"
      end

      if updates.empty?
        return {
          success: true,
          message: "No changes made to memory ##{memory.id} - provided values match existing content",
          memory_id: memory.id,
          memory_type: memory.memory_type,
          unchanged: true
        }
      end

      # Create a version before updating
      change_desc = updates.join(", ")
      memory.create_version!(
        created_by: context[:user],
        change_reason: "Before update: #{change_desc}"
      )

      memory.updated_by = context[:user]
      memory.save!

      {
        success: true,
        message: "Updated memory ##{memory.id}: #{memory.title} (#{updates.join(', ')})",
        memory_id: memory.id,
        memory_type: memory.memory_type,
        updated_fields: updates
      }
    rescue => e
      { error: "Failed to update memory: #{e.message}" }
    end

    private

    def valid_memory_type(type)
      return type if Memory::MEMORY_TYPES.include?(type)
      "knowledge"
    end
  end
end
