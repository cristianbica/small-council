# frozen_string_literal: true

module AI
  module Tools
    module Advisors
      class CreateAdvisorTool < AbstractTool
        self.requires_approval = true
        self.read_only = false

        description "Create a new advisor in this space"

        params do
          string :name, description: "Name of the advisor", required: true
          string :system_prompt, description: "System prompt for the advisor", required: true
          string :short_description, description: "Short description for the advisor", required: false
        end

        def execute(name:, system_prompt:, short_description: nil)
          return { success: false, error: "name is required" } if name.blank?
          return { success: false, error: "system_prompt is required" } if system_prompt.blank?

          space = context[:space]
          advisor = space.advisors.create!(
            account: space.account,
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
      end
    end
  end
end
