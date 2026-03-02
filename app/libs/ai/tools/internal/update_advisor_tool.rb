# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Update an advisor's attributes
      class UpdateAdvisorTool < BaseTool
        def description
          "Update an existing advisor's profile details. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              advisor_id: {
                type: "integer",
                description: "ID of the advisor to update (required)"
              },
              name: {
                type: "string",
                description: "New name for the advisor"
              },
              short_description: {
                type: "string",
                description: "New short description for the advisor"
              },
              system_prompt: {
                type: "string",
                description: "New system prompt for the advisor"
              }
            },
            required: [ :advisor_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          advisor_id = arguments[:advisor_id] || arguments["advisor_id"]
          name = arguments[:name] || arguments["name"]
          short_description = arguments[:short_description] || arguments["short_description"]
          system_prompt = arguments[:system_prompt] || arguments["system_prompt"]

          if advisor_id.blank?
            return { success: false, error: "advisor_id is required" }
          end

          space = context[:space]
          advisor = space.advisors.find_by(id: advisor_id)

          unless advisor
            return { success: false, error: "Advisor not found with ID: #{advisor_id}" }
          end

          if advisor.is_scribe
            return { success: false, error: "Cannot update the Scribe advisor" }
          end

          update_attrs = {}
          update_attrs[:name] = name if name.present?
          update_attrs[:short_description] = short_description if short_description.present?
          update_attrs[:system_prompt] = system_prompt if system_prompt.present?

          if update_attrs.empty?
            return { success: false, error: "No fields to update. Provide name, short_description, or system_prompt." }
          end

          advisor.update!(update_attrs)

          {
            success: true,
            advisor_id: advisor.id,
            name: advisor.name,
            message: "Advisor updated successfully"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to update advisor: #{e.message}" }
        end

        private
      end
    end
  end
end
