# frozen_string_literal: true

module AI
  module Agents
    class AdvisorAgent < BaseAgent
      self.system_prompt = "agents/advisor"

      def tools
        return [ "memories/*" ] if @context.respond_to?(:scribe?) && @context.scribe?

        []
      end

      def system_prompt
        @system_prompt ||= AI.prompt(self.class.system_prompt, context: @context)
      end
    end
  end
end
