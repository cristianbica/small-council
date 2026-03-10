# frozen_string_literal: true

module AI
  module Tools
    module Memories
      class CreateMemoryTool < AbstractTool
        self.requires_approval = true
        self.read_only = false

        description "Create a new memory record with a title and content"

        params do
          string :title, description: "Title of the memory", required: true
          string :content, description: "Content of the memory", required: true
          string :memory_type, description: "Type of memory", required: false, enum: Memory::MEMORY_TYPES
        end

        def execute(title:, content:, memory_type: "knowledge")
          return { success: false, error: "title is required" } if title.blank?
          return { success: false, error: "content is required" } if content.blank?

          memory_type = "knowledge" unless Memory::MEMORY_TYPES.include?(memory_type.to_s)

          space = context[:space]
          creator = context[:advisor] || context[:user]

          memory = space.memories.create!(
            account: space.account,
            title: title,
            content: content,
            memory_type: memory_type,
            status: "active",
            created_by: creator,
            updated_by: creator
          )

          {
            success: true,
            memory_id: memory.id,
            title: memory.title,
            memory_type: memory.memory_type,
            message: "Memory created successfully"
          }
        rescue ActiveRecord::RecordInvalid => e
          { success: false, error: "Failed to create memory: #{e.message}" }
        end
      end
    end
  end
end
