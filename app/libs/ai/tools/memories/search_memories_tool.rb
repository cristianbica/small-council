# frozen_string_literal: true

module AI
  module Tools
    module Memories
      class SearchMemoriesTool < AbstractTool
        self.requires_approval = false
        self.read_only = true

        description "Search memories by keyword or phrase"

        params do
          string :query, description: "Search term to find in titles or content", required: true
          string :memory_type, description: "Filter by memory type", required: false, enum: Memory::MEMORY_TYPES
          integer :limit, description: "Maximum results (default: 5, max: 10)", required: false
        end

        def execute(query:, memory_type: nil, limit: 5)
          return { success: false, error: "query is required", memories: [] } if query.blank?

          limit = limit.to_i
          limit = 5 if limit < 1
          limit = 10 if limit > 10

          space = context[:space]
          scope = space.memories.active
          scope = scope.where(memory_type: memory_type) if memory_type.present? && Memory::MEMORY_TYPES.include?(memory_type.to_s)
          scope = scope.where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")

          memories = scope.recent.limit(limit)

          return { success: true, message: "No memories found", query: query, memories: [] } if memories.empty?

          {
            success: true,
            message: "Found #{memories.size} memories",
            query: query,
            count: memories.size,
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
            preview: memory.content.truncate(200),
            updated_at: memory.updated_at.strftime("%Y-%m-%d %H:%M"),
            created_by: memory.creator_display
          }
        end
      end
    end
  end
end
