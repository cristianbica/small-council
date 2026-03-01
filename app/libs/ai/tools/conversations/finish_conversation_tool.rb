# frozen_string_literal: true

module AI
  module Tools
    module Conversations
      # Mark conversation as finished
      # This tool triggers the conversation conclusion process
      class FinishConversationTool < BaseTool
        def description
          "Mark this conversation as finished. Triggers final summary and memory creation. Only use when the discussion has reached a natural conclusion."
        end

        def parameters
          {
            type: "object",
            properties: {
              reason: {
                type: "string",
                description: "Why the conversation is being finished (e.g., 'resolved', 'no further questions', 'decision reached')"
              }
            },
            required: [ :reason ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :conversation)

          reason = arguments[:reason] || arguments["reason"]

          if reason.blank?
            return { success: false, error: "reason is required" }
          end

          conversation = context[:conversation]

          # Check if already concluding or resolved
          if conversation.concluding? || conversation.resolved? || conversation.archived?
            return {
              success: false,
              error: "Conversation is already #{conversation.status}",
              conversation_id: conversation.id,
              status: conversation.status
            }
          end

          # Begin conclusion process
          lifecycle = ConversationLifecycle.new(conversation)
          lifecycle.begin_conclusion_process

          # Update with reason
          conversation.update_column(:context, conversation.context.merge(
            "conclusion_reason" => reason,
            "concluded_by" => context[:advisor]&.name || context[:user]&.email || "unknown"
          ))

          {
            success: true,
            message: "Conversation marked as finishing. Summary will be generated.",
            conversation_id: conversation.id,
            reason: reason,
            status: "concluding"
          }
        end
      end
    end
  end
end
