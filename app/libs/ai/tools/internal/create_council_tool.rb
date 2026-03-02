# frozen_string_literal: true

module AI
  module Tools
    module Internal
      # Create a new council in the current space
      class CreateCouncilTool < BaseTool
        def description
          "Create a new council in this space. Use this to define a council with advisors. Scribe-only."
        end

        def parameters
          {
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Name of the council (required)"
              },
              description: {
                type: "string",
                description: "Description of the council"
              },
              visibility: {
                type: "string",
                enum: Council.visibilities.values.uniq,
                description: "Council visibility (private or shared)"
              },
              advisor_ids: {
                type: "array",
                items: { type: "integer" },
                description: "Advisor IDs to assign to the council"
              }
            },
            required: [ :name ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space, :user)

          name = arguments[:name] || arguments["name"]
          description = arguments[:description] || arguments["description"]
          visibility = arguments[:visibility] || arguments["visibility"]
          advisor_ids = arguments[:advisor_ids] || arguments["advisor_ids"] || []

          if name.blank?
            return { success: false, error: "name is required" }
          end

          space = context[:space]
          account = space.account
          user = context[:user]

          council = space.councils.new(
            account: account,
            user: user,
            name: name,
            description: description,
            visibility: normalized_visibility(visibility)
          )
          advisor_ids = JSON.parse(advisor_ids) if advisor_ids.is_a?(String)
          advisor_ids = Array(advisor_ids).uniq.map(&:to_i)
          if advisor_ids.any?
            missing_ids = advisor_ids - space.advisors.where(id: advisor_ids).pluck(:id)
            if missing_ids.any?
              return { success: false, error: "advisor_ids not found in this space: #{missing_ids.join(', ')}" }
            end
          end

          council.save!

          assign_advisors(council, space, advisor_ids)
          council.ensure_scribe_assigned

          {
            success: true,
            council_id: council.id,
            name: council.name,
            message: "Council created successfully"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to create council: #{e.message}" }
        end

        private

        def normalized_visibility(value)
          return "private" if value.blank?

          visibility = Council.visibilities[value.to_s] || value.to_s
          return visibility if Council.visibilities.value?(visibility)

          "private"
        end

        def assign_advisors(council, space, advisor_ids)
          Array(advisor_ids).each do |advisor_id|
            advisor = space.advisors.find_by(id: advisor_id)
            next unless advisor
            next if council.advisors.include?(advisor)

            council.advisors << advisor
          end
        end
      end
    end
  end
end
