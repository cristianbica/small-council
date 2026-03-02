# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Get council details by ID
      class GetCouncilTool < BaseTool
        def description
          "Get full details for a specific council by ID. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              council_id: {
                type: "integer",
                description: "ID of the council to fetch (required)"
              }
            },
            required: [ :council_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          council_id = arguments[:council_id] || arguments["council_id"]

          if council_id.blank?
            return { success: false, error: "council_id is required" }
          end

          space = context[:space]
          council = space.councils.find_by(id: council_id)

          unless council
            return { success: false, error: "Council not found with ID: #{council_id}" }
          end

          {
            success: true,
            council: format_council(council)
          }
        end

        private

        def format_council(council)
          {
            id: council.id,
            name: council.name,
            description: council.description,
            visibility: council.visibility,
            memory: council.memory,
            configuration: council.configuration || {},
            advisor_ids: council.advisor_ids,
            space_id: council.space_id,
            user_id: council.user_id,
            created_at: council.created_at.strftime("%Y-%m-%d %H:%M"),
            updated_at: council.updated_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      end
    end
  end
end
