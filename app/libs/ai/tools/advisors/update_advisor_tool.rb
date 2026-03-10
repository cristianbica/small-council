# frozen_string_literal: true

module AI
  module Tools
    module Advisors
      class UpdateAdvisorTool < AbstractTool
        self.requires_approval = true
        self.read_only = false

        description "Update an existing advisor's profile"

        params do
          integer :advisor_id, description: "ID of the advisor to update", required: true
          string :name, description: "New name for the advisor", required: false
          string :short_description, description: "New short description", required: false
          string :system_prompt, description: "New system prompt", required: false
        end

        def execute(advisor_id:, name: nil, short_description: nil, system_prompt: nil)
          return { success: false, error: "advisor_id is required" } if advisor_id.blank?

          space = context[:space]
          advisor = space.advisors.find_by(id: advisor_id)

          return { success: false, error: "Advisor not found" } unless advisor
          return { success: false, error: "Cannot update the Scribe advisor" } if advisor.is_scribe

          update_attrs = {}
          update_attrs[:name] = name if name.present?
          update_attrs[:short_description] = short_description if short_description.present?
          update_attrs[:system_prompt] = system_prompt if system_prompt.present?

          return { success: false, error: "No fields to update" } if update_attrs.empty?

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
      end
    end
  end
end
