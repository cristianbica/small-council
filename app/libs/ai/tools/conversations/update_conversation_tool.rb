# frozen_string_literal: true

module AI
  module Tools
    module Conversations
      class UpdateConversationTool < AbstractTool
        self.requires_approval = false
        self.read_only = false

        description "Update conversation fields (title only) for the current conversation"

        params do
          integer :conversation_id, description: "ID of the conversation to update", required: true
          string :title, description: "New conversation title", required: true
        end

        def execute(conversation_id:, title:)
          conversation = context[:conversation]
          return { success: false, error: "Conversation context is required" } unless conversation

          requested_id = conversation_id.to_i
          if conversation.id != requested_id
            return {
              success: false,
              error: "Conversation mismatch: tool can only update the current conversation"
            }
          end

          normalized_title = title.to_s.squish.first(255)
          return { success: false, error: "title is required" } if normalized_title.blank?

          conversation.update!(title: normalized_title, title_state: :agent_generated)

          {
            success: true,
            conversation_id: conversation.id,
            title: conversation.title,
            title_state: conversation.title_state
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to update conversation: #{e.message}" }
        end
      end
    end
  end
end
