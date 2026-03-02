# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # List advisors in the current space
      class ListAdvisorsTool < BaseTool
        def description
          "List advisors in this space with pagination. Use this to browse available advisor profiles. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              include_scribe: {
                type: "boolean",
                description: "Include the Scribe advisor (default: false)"
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

          include_scribe = arguments[:include_scribe]
          include_scribe = arguments["include_scribe"] if include_scribe.nil?
          limit = arguments[:limit] || arguments["limit"]
          offset = arguments[:offset] || arguments["offset"]

          limit = limit.to_i
          limit = 10 if limit < 1
          limit = 20 if limit > 20

          offset = offset.to_i
          offset = 0 if offset < 0

          space = context[:space]
          scope = space.advisors.order(:name)
          scope = scope.where(is_scribe: false) unless include_scribe

          total_count = scope.count
          advisors = scope.limit(limit).offset(offset)

          {
            success: true,
            count: advisors.count,
            total_count: total_count,
            limit: limit,
            offset: offset,
            has_more: (offset + advisors.count) < total_count,
            advisors: advisors.map { |advisor| format_advisor(advisor) }
          }
        end

        private

        def format_advisor(advisor)
          {
            id: advisor.id,
            name: advisor.name,
            short_description: advisor.short_description,
            is_scribe: advisor.is_scribe,
            space_id: advisor.space_id,
            llm_model_id: advisor.llm_model_id,
            created_at: advisor.created_at.strftime("%Y-%m-%d %H:%M"),
            updated_at: advisor.updated_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      end
    end
  end
end
