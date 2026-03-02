# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Update a council's attributes
      class UpdateCouncilTool < BaseTool
        def description
          "Update an existing council's details. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              council_id: {
                type: "integer",
                description: "ID of the council to update (required)"
              },
              name: {
                type: "string",
                description: "New name for the council"
              },
              description: {
                type: "string",
                description: "New description for the council"
              },
              visibility: {
                type: "string",
                enum: Council.visibilities.values.uniq,
                description: "Council visibility (private or shared)"
              },
              memory: {
                type: "string",
                description: "Council memory text"
              }
            },
            required: [ :council_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          council_id = arguments[:council_id] || arguments["council_id"]
          name = arguments[:name] || arguments["name"]
          description = arguments[:description] || arguments["description"]
          visibility = arguments[:visibility] || arguments["visibility"]
          memory = arguments[:memory] || arguments["memory"]

          if council_id.blank?
            return { success: false, error: "council_id is required" }
          end

          space = context[:space]
          council = space.councils.find_by(id: council_id)

          unless council
            return { success: false, error: "Council not found with ID: #{council_id}" }
          end

          update_attrs = {}
          update_attrs[:name] = name if name.present?
          update_attrs[:description] = description if description.present?
          update_attrs[:memory] = memory if memory.present?

          if visibility.present?
            normalized = Council.visibilities[visibility.to_s] || visibility.to_s
            unless Council.visibilities.value?(normalized)
              return { success: false, error: "visibility must be one of: #{Council.visibilities.values.uniq.join(', ')}" }
            end

            update_attrs[:visibility] = normalized
          end

          if update_attrs.empty?
            return { success: false, error: "No fields to update. Provide name, description, visibility, or memory." }
          end

          council.update!(update_attrs)

          {
            success: true,
            council_id: council.id,
            name: council.name,
            message: "Council updated successfully"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to update council: #{e.message}" }
        end

        private
      end
    end
  end
end
