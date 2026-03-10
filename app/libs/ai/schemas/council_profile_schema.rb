# frozen_string_literal: true

module AI
  module Schemas
    class CouncilProfileSchema
      def to_json_schema
        {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Concise council name in title case"
            },
            description: {
              type: "string",
              description: "Brief council description"
            }
          },
          required: %w[name description],
          additionalProperties: false
        }
      end
    end
  end
end
