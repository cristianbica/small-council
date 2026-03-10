# frozen_string_literal: true

module AI
  module Tools
    module Memories
      class FetchMemoryTool < AbstractTool
        self.requires_approval = false
        self.read_only = true

        description "Fetch full content of a specific memory by ID"

        params do
          integer :memory_id, description: "ID of the memory to fetch", required: true
        end

        def execute(memory_id:)
          return { success: false, error: "memory_id is required" } if memory_id.blank?

          space = context[:space]
          memory = space.memories.find_by(id: memory_id)

          return { success: false, error: "Memory not found" } unless memory

          {
            success: true,
            memory: {
              id: memory.id,
              title: memory.title,
              content: memory.content,
              type: memory.memory_type,
              status: memory.status,
              metadata: memory.metadata || {},
              created_at: memory.created_at.strftime("%Y-%m-%d %H:%M"),
              updated_at: memory.updated_at.strftime("%Y-%m-%d %H:%M"),
              created_by: memory.creator_display,
              source: memory.source_display
            }
          }
        end
      end
    end
  end
end
