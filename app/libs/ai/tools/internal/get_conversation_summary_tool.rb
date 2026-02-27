# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Get the stored summary for a conversation
      class GetConversationSummaryTool < BaseTool
        def description
          "Get the stored summary for a specific conversation if one exists. This retrieves previously generated summaries, not creating new ones."
        end

        def parameters
          {
            type: "object",
            properties: {
              conversation_id: {
                type: "integer",
                description: "ID of the conversation to get summary for (required)"
              }
            },
            required: [ :conversation_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          conversation_id = arguments[:conversation_id] || arguments["conversation_id"]

          if conversation_id.blank?
            return { success: false, error: "conversation_id is required" }
          end

          space = context[:space]
          conversation = space.conversations.find_by(id: conversation_id)

          unless conversation
            return {
              success: false,
              error: "Conversation not found with ID: #{conversation_id}"
            }
          end

          # Look for a conversation_summary memory associated with this conversation
          summary_memory = space.memories
                                .where(source: conversation)
                                .where(memory_type: "conversation_summary")
                                .active
                                .recent
                                .first

          if summary_memory
            return {
              success: true,
              found: true,
              conversation_id: conversation.id,
              conversation_title: conversation.title,
              summary: summary_memory.content,
              memory_id: summary_memory.id,
              created_at: summary_memory.created_at.strftime("%Y-%m-%d %H:%M"),
              updated_at: summary_memory.updated_at.strftime("%Y-%m-%d %H:%M")
            }
          end

          # Also check the conversation's own memory field
          memory_data = conversation.memory_data
          if memory_data.present? && memory_data["summary"].present?
            return {
              success: true,
              found: true,
              conversation_id: conversation.id,
              conversation_title: conversation.title,
              summary: memory_data["summary"],
              source: "conversation.memory",
              created_at: conversation.updated_at.strftime("%Y-%m-%d %H:%M")
            }
          end

          {
            success: true,
            found: false,
            conversation_id: conversation.id,
            conversation_title: conversation.title,
            message: "No stored summary found for this conversation. The conversation may not be concluded yet.",
            status: conversation.status
          }
        end
      end
    end
  end
end
