# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # List councils in the current space
      class ListCouncilsTool < BaseTool
        def description
          "List councils in this space with pagination. Use this to browse available councils. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              visibility: {
                type: "string",
                enum: Council.visibilities.values.uniq,
                description: "Filter by visibility (optional)"
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

          visibility = arguments[:visibility] || arguments["visibility"]
          limit = arguments[:limit] || arguments["limit"]
          offset = arguments[:offset] || arguments["offset"]

          limit = limit.to_i
          limit = 10 if limit < 1
          limit = 20 if limit > 20

          offset = offset.to_i
          offset = 0 if offset < 0

          space = context[:space]
          scope = space.councils.order(:created_at)

          if visibility.present?
            normalized = Council.visibilities[visibility.to_s] || visibility.to_s
            scope = scope.where(visibility: normalized) if Council.visibilities.value?(normalized)
          end

          total_count = scope.count
          councils = scope.limit(limit).offset(offset)

          {
            success: true,
            count: councils.count,
            total_count: total_count,
            limit: limit,
            offset: offset,
            has_more: (offset + councils.count) < total_count,
            councils: councils.map { |council| format_council(council) }
          }
        end

        private

        def format_council(council)
          {
            id: council.id,
            name: council.name,
            description: council.description,
            visibility: council.visibility,
            advisor_count: council.advisors.count,
            space_id: council.space_id,
            created_at: council.created_at.strftime("%Y-%m-%d %H:%M"),
            updated_at: council.updated_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      end
    end
  end
end
