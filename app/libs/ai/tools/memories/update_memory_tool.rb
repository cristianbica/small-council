# frozen_string_literal: true

module AI
  module Tools
    module Memories
      class UpdateMemoryTool < AbstractTool
        self.requires_approval = true
        self.read_only = false

        description "Update an existing memory's title or content"

        params do
          integer :memory_id, description: "ID of the memory to update", required: true
          string :title, description: "New title for the memory", required: false
          string :content, description: "New content for the memory", required: false
          string :change_reason, description: "Reason for this update", required: false
        end

        def execute(memory_id:, title: nil, content: nil, change_reason: "Updated via AI tool")
          return { success: false, error: "memory_id is required" } if memory_id.blank?

          space = context[:space]
          memory = space.memories.find_by(id: memory_id)

          return { success: false, error: "Memory not found" } unless memory

          updater = context[:advisor] || context[:user]

          update_attrs = {}
          update_attrs[:title] = title if title.present?
          update_attrs[:content] = content if content.present?

          return { success: false, error: "No fields to update" } if update_attrs.empty?

          update_attrs[:updated_by] = updater
          memory.update!(update_attrs)

          {
            success: true,
            memory_id: memory.id,
            title: memory.title,
            message: "Memory updated successfully"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to update memory: #{e.message}" }
        end
      end
    end
  end
end
