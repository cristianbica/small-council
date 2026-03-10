# frozen_string_literal: true

module AI
  module Schemas
    class AdvisorProfileSchema
      def to_json_schema
        {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Concise advisor name in title case"
            },
            short_description: {
              type: "string",
              description: "Brief advisor description for list views"
            },
            system_prompt: {
              type: "string",
              description: "Full advisor system prompt"
            }
          },
          required: %w[name short_description system_prompt],
          additionalProperties: false
        }
      end
    end
  end
end
