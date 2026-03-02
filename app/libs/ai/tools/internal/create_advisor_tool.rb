# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Create a new advisor in the current space
      class CreateAdvisorTool < BaseTool
        def description
          "Create a new advisor in this space. Use this to add new advisor profiles for the council. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Name of the advisor (required)"
              },
              system_prompt: {
                type: "string",
                description: "System prompt for the advisor (required)"
              },
              short_description: {
                type: "string",
                description: "Short description for the advisor"
              }
            },
            required: [ :name, :system_prompt ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          name = arguments[:name] || arguments["name"]
          system_prompt = arguments[:system_prompt] || arguments["system_prompt"]
          short_description = arguments[:short_description] || arguments["short_description"]

          if name.blank?
            return { success: false, error: "name is required" }
          end

          if system_prompt.blank?
            return { success: false, error: "system_prompt is required" }
          end

          space = context[:space]
          account = space.account

          advisor = space.advisors.create!(
            account: account,
            name: name,
            system_prompt: system_prompt,
            short_description: short_description,
            is_scribe: false
          )

          {
            success: true,
            advisor_id: advisor.id,
            name: advisor.name,
            message: "Advisor created successfully"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to create advisor: #{e.message}" }
        end

        private
      end
    end
  end
end
