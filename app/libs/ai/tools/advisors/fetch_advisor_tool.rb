# frozen_string_literal: true

module AI
  module Tools
    module Advisors
      class FetchAdvisorTool < AbstractTool
        self.requires_approval = false
        self.read_only = true

        description "Fetch full details for a specific advisor by ID"

        params do
          integer :advisor_id, description: "ID of the advisor to fetch", required: true
        end

        def execute(advisor_id:)
          return { success: false, error: "advisor_id is required" } if advisor_id.blank?

          space = context[:space]
          advisor = space.advisors.find_by(id: advisor_id)

          return { success: false, error: "Advisor not found" } unless advisor

          {
            success: true,
            advisor: {
              id: advisor.id,
              name: advisor.name,
              short_description: advisor.short_description,
              system_prompt: advisor.system_prompt,
              is_scribe: advisor.is_scribe,
              space_id: advisor.space_id,
              llm_model_id: advisor.llm_model_id,
              metadata: advisor.metadata || {},
              model_config: advisor.model_config || {},
              created_at: advisor.created_at.strftime("%Y-%m-%d %H:%M"),
              updated_at: advisor.updated_at.strftime("%Y-%m-%d %H:%M")
            }
          }
        end
      end
    end
  end
end
