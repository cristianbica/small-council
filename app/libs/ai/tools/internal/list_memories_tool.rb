# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # List memories with pagination
      class ListMemoriesTool < BaseTool
        def description
          "List memories in this space with pagination. Use to browse available memories without searching."
        end

        def parameters
          {
            type: "object",
            properties: {
              memory_type: {
                type: "string",
                enum: Memory::MEMORY_TYPES,
                description: "Filter by memory type (optional)"
              },
              limit: {
                type: "integer",
                description: "Maximum number of results to return (default: 10, max: 20)",
                minimum: 1,
                maximum: 20
              },
              offset: {
                type: "integer",
                description: "Number of results to skip (for pagination)",
                minimum: 0
              }
            },
            required: []
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          memory_type = arguments[:memory_type] || arguments["memory_type"]
          limit = arguments[:limit] || arguments["limit"]
          offset = arguments[:offset] || arguments["offset"]

          # Apply limit bounds
          limit = limit.to_i
          limit = 10 if limit < 1
          limit = 20 if limit > 20

          offset = offset.to_i
          offset = 0 if offset < 0

          space = context[:space]
          scope = space.memories.active

          # Apply memory type filter if valid
          if memory_type.present? && Memory::MEMORY_TYPES.include?(memory_type.to_s)
            scope = scope.where(memory_type: memory_type)
          end

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
            tags: memory.metadata&.dig("tags") || [],
            updated_at: memory.updated_at.strftime("%Y-%m-%d %H:%M"),
            created_by: memory.creator_display
          }
        end
      end
    end
  end
end
