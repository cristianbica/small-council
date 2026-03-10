# frozen_string_literal: true

module AI
  module Tools
    module Memories
      class ListMemoriesTool < AbstractTool
        self.requires_approval = false
        self.read_only = true

        description "List memories in this space with pagination"

        params do
          string :memory_type, description: "Filter by memory type", required: false, enum: Memory::MEMORY_TYPES
          integer :limit, description: "Maximum results (default: 10, max: 20)", required: false
          integer :offset, description: "Results to skip for pagination", required: false
        end

        def execute(memory_type: nil, limit: 10, offset: 0)
          limit = limit.to_i
          limit = 10 if limit < 1
          limit = 20 if limit > 20

          offset = offset.to_i
          offset = 0 if offset < 0

          space = context[:space]
          scope = space.memories.active
          scope = scope.where(memory_type: memory_type) if memory_type.present? && Memory::MEMORY_TYPES.include?(memory_type.to_s)

          total_count = scope.count
          memories = scope.recent.limit(limit).offset(offset)

          {
            success: true,
            count: memories.count,
            total_count: total_count,
            limit: limit,
            offset: offset,
            has_more: (offset + memories.count) < total_count,
            memories: memories.map { |m| format_memory(m) }
          }
        end

        private

        def format_memory(memory)
          {
            id: memory.id,
            title: memory.title,
            type: memory.memory_type,
            status: memory.status,
            preview: memory.content_preview,
            updated_at: memory.updated_at.strftime("%Y-%m-%d %H:%M"),
            created_by: memory.creator_display
          }
        end
      end
    end
  end
end
