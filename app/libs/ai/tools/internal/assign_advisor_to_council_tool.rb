# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Assign an advisor to a council
      class AssignAdvisorToCouncilTool < BaseTool
        def description
          "Assign an advisor to a council. Use this to add advisors to an existing council. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              council_id: {
                type: "integer",
                description: "ID of the council (required)"
              },
              advisor_id: {
                type: "integer",
                description: "ID of the advisor to assign (required)"
              },
              position: {
                type: "integer",
                description: "Optional position for the advisor in the council",
                minimum: 0
              }
            },
            required: [ :council_id, :advisor_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          council_id = arguments[:council_id] || arguments["council_id"]
          advisor_id = arguments[:advisor_id] || arguments["advisor_id"]
          position = arguments[:position] || arguments["position"]

          if council_id.blank?
            return { success: false, error: "council_id is required" }
          end

          if advisor_id.blank?
            return { success: false, error: "advisor_id is required" }
          end

          space = context[:space]
          council = space.councils.find_by(id: council_id)
          return { success: false, error: "Council not found with ID: #{council_id}" } unless council

          advisor = space.advisors.find_by(id: advisor_id)
          return { success: false, error: "Advisor not found with ID: #{advisor_id}" } unless advisor

          if council.advisors.exists?(advisor.id)
            return { success: false, error: "Advisor already assigned to council" }
          end

          join = council.council_advisors.new(advisor: advisor)
          join.position = position.to_i if position.present?
          join.save!

          {
            success: true,
            council_id: council.id,
            advisor_id: advisor.id,
            message: "Advisor assigned to council"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to assign advisor: #{e.message}" }
        end

        private
      end
    end
  end
end
