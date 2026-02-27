# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Read full memory content by ID
      class ReadMemoryTool < BaseTool
        def description
          "Read the full content of a specific memory by its ID. Use this to get complete details of a memory."
        end

        def parameters
          {
            type: "object",
            properties: {
              memory_id: {
                type: "integer",
                description: "ID of the memory to read (required)"
              }
            },
            required: [ :memory_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          memory_id = arguments[:memory_id] || arguments["memory_id"]

          if memory_id.blank?
            return { success: false, error: "memory_id is required" }
          end

          space = context[:space]
          memory = space.memories.find_by(id: memory_id)

          unless memory
            return {
              success: false,
              error: "Memory not found with ID: #{memory_id}"
            }
          end

          {
            success: true,
            memory: format_full_memory(memory)
          }
        end

        private

        def format_full_memory(memory)
          {
            id: memory.id,
            title: memory.title,
            content: memory.content,
            type: memory.memory_type,
            status: memory.status,
            tags: memory.metadata&.dig("tags") || [],
            metadata: memory.metadata || {},
            created_at: memory.created_at.strftime("%Y-%m-%d %H:%M"),
            updated_at: memory.updated_at.strftime("%Y-%m-%d %H:%M"),
            created_by: memory.creator_display,
            source: memory.source_display
          }
        end
      end
    end
  end
end
