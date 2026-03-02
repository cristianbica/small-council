# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Get advisor details by ID
      class GetAdvisorTool < BaseTool
        def description
          "Get full details for a specific advisor by ID. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              advisor_id: {
                type: "integer",
                description: "ID of the advisor to fetch (required)"
              }
            },
            required: [ :advisor_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          advisor_id = arguments[:advisor_id] || arguments["advisor_id"]

          if advisor_id.blank?
            return { success: false, error: "advisor_id is required" }
          end

          space = context[:space]
          advisor = space.advisors.find_by(id: advisor_id)

          unless advisor
            return { success: false, error: "Advisor not found with ID: #{advisor_id}" }
          end

          {
            success: true,
            advisor: format_advisor(advisor)
          }
        end

        private

        def format_advisor(advisor)
          {
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
        end
      end
    end
  end
end
