# frozen_string_literal: true

module AI
  module Tools
    module Advisors
      class ListAdvisorsTool < AbstractTool
        self.requires_approval = false
        self.read_only = true

        description "List advisors in this space"

        params do
          boolean :include_scribe, description: "Include the Scribe advisor", required: false
          integer :limit, description: "Maximum results (default: 10, max: 20)", required: false
          integer :offset, description: "Results to skip for pagination", required: false
        end

        def execute(include_scribe: false, limit: 10, offset: 0)
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
            advisors: advisors.map { |a| format_advisor(a) }
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
