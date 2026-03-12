# frozen_string_literal: true

module AI
  module Trackers
    class VersionsTracker
      attr_reader :task, :context

      def initialize(task: nil, context: nil, **)
        @task = task
        @context = context
        @saved_contexts = {}
      end

      def track(result)
        # No-op: VersionsTracker works via callbacks (before_tool_call/after_tool_call)
      end

      def register(chat)
        chat.before_tool_call do |tool_call|
          next unless write_tool?(tool_call.name)

          # Save current values
          tool_call_id = tool_call.id
          @saved_contexts[tool_call_id] = {
            version_whodunnit: Current.version_whodunnit,
            version_metadata: Current.version_metadata
          }

          # Set new values (nil is valid for whodunnit)
          whodunnit = context[:advisor]
          Current.version_whodunnit = whodunnit
          Current.version_metadata = {
            tool: tool_call.name,
            tool_call_id: tool_call.id
          }
        rescue => e
          Rails.logger.error "[VersionsTracker] before_tool_call failed: #{e.message}"
        end

        chat.after_tool_call do |tool_call, result|
          tool_call_id = tool_call.id
          saved = @saved_contexts.delete(tool_call_id)

          # Restore previous values (could be nil, which is correct)
          if saved
            Current.version_whodunnit = saved[:version_whodunnit]
            Current.version_metadata = saved[:version_metadata]
          end
        rescue => e
          Rails.logger.error "[VersionsTracker] after_tool_call failed: #{e.message}"
        end
      end

      private

      def write_tool?(tool_name)
        !AI.tool(tool_name.parameterize(separator: "/"))&.read_only
      rescue AI::ResolutionError
        false
      end
    end
  end
end
