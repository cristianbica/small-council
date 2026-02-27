# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Search for memories in the current space by keyword
      #
      # This tool allows AI agents to query the memory system for relevant
      # information beyond what is auto-fed in the context.
      #
      # Example usage:
      #   tool = QueryMemoriesTool.new
      #   result = tool.execute(
      #     { query: "project timeline", memory_type: "knowledge", limit: 5 },
      #     { space: my_space }
      #   )
      #
      class QueryMemoriesTool < BaseTool
        def description
          "Search for memories in this space by keyword or phrase. Use this to find relevant information beyond the auto-fed summary."
        end

        def parameters
          {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search term or keyword to find relevant memories (required)"
              },
              memory_type: {
                type: "string",
                description: "Optional filter by type: summary, knowledge, conversation_summary, conversation_notes",
                enum: Memory::MEMORY_TYPES
              },
              limit: {
                type: "integer",
                description: "Maximum number of results to return (default: 5, max: 10)",
                minimum: 1,
                maximum: 10
              }
            },
            required: [ :query ]
          }
        end

        # Execute the search
        #
        # @param arguments [Hash] Contains :query, optional :memory_type, optional :limit
        # @param context [Hash] Must contain :space (Space instance)
        # @return [Hash] Search results
        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          query = arguments[:query] || arguments["query"]
          memory_type = arguments[:memory_type] || arguments["memory_type"]
          limit = arguments[:limit] || arguments["limit"]

          if query.blank?
            return {
              success: false,
              error: "Query parameter is required",
              memories: []
            }
          end

          # Apply limit bounds
          limit = limit.to_i
          limit = 10 if limit > 10
          limit = 5 if limit < 1

          space = context[:space]
          scope = space.memories.active

          # Apply memory type filter if valid
          if memory_type.present? && Memory::MEMORY_TYPES.include?(memory_type)
            scope = scope.where(memory_type: memory_type)
          end

          # Search by title or content
          scope = scope.where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")

          memories = scope.recent.limit(limit)

          if memories.empty?
            return {
              success: true,
              message: "No memories found matching '#{query}'",
              query: query,
              memory_type: memory_type,
              memories: []
            }
          end

          {
            success: true,
            message: "Found #{memories.size} memory/ies matching '#{query}'",
            query: query,
            memory_type: memory_type,
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
