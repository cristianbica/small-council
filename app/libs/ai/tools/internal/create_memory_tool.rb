# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Create a new memory record with a title and content
      class CreateMemoryTool < BaseTool
        def description
          "Create a new memory record with a title and content. Use this to save important information to the space's knowledge base."
        end

        def parameters
          {
            type: "object",
            properties: {
              title: {
                type: "string",
                description: "Title of the memory (required)"
              },
              content: {
                type: "string",
                description: "Content of the memory (required)"
              },
              memory_type: {
                type: "string",
                enum: Memory::MEMORY_TYPES,
                description: "Type of memory: summary, knowledge, conversation_summary, conversation_notes (default: knowledge)"
              },
              tags: {
                type: "array",
                items: { type: "string" },
                description: "Optional tags for the memory"
              }
            },
            required: [ :title, :content ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          title = arguments[:title] || arguments["title"]
          content = arguments[:content] || arguments["content"]
          memory_type = arguments[:memory_type] || arguments["memory_type"] || "knowledge"
          tags = arguments[:tags] || arguments["tags"] || []

          if title.blank?
            return { success: false, error: "title is required" }
          end

          if content.blank?
            return { success: false, error: "content is required" }
          end

          # Validate memory type
          unless Memory::MEMORY_TYPES.include?(memory_type.to_s)
            memory_type = "knowledge"
          end

          space = context[:space]
          creator = context[:advisor] || context[:user]

          # Store tags in metadata since there's no tags column
          metadata = { "tags" => Array(tags) }

          memory = space.memories.create!(
            account: space.account,
            title: title,
            content: content,
            memory_type: memory_type,
            metadata: metadata,
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
          {
            success: false,
            error: "Failed to create memory: #{e.message}"
          }
        end
      end
    end
  end
end
