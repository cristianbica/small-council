# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Remove an advisor from a council
      class UnassignAdvisorFromCouncilTool < BaseTool
        def description
          "Unassign an advisor from a council. Use this to remove advisors from an existing council. Scribe-only."
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
                description: "ID of the advisor to unassign (required)"
              }
            },
            required: [ :council_id, :advisor_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          council_id = arguments[:council_id] || arguments["council_id"]
          advisor_id = arguments[:advisor_id] || arguments["advisor_id"]

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

          join = council.council_advisors.find_by(advisor: advisor)
          return { success: false, error: "Advisor is not assigned to this council" } unless join

          if advisor.is_scribe
            return { success: false, error: "Cannot unassign the Scribe advisor" }
          end

          join.destroy!

          {
            success: true,
            council_id: council.id,
            advisor_id: advisor.id,
            message: "Advisor unassigned from council"
          }
        end

        private
      end
    end
  end
end
