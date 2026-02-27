# frozen_string_literal: true


module AI
  module Tools
    module Internal
      # Update an existing memory
      class UpdateMemoryTool < BaseTool
        def description
          "Update an existing memory's title, content, or tags. Creates a version record before updating."
        end

        def parameters
          {
            type: "object",
            properties: {
              memory_id: {
                type: "integer",
                description: "ID of the memory to update (required)"
              },
              title: {
                type: "string",
                description: "New title for the memory"
              },
              content: {
                type: "string",
                description: "New content for the memory"
              },
              tags: {
                type: "array",
                items: { type: "string" },
                description: "New tags for the memory"
              },
              change_reason: {
                type: "string",
                description: "Reason for this update (for version history)"
              }
            },
            required: [ :memory_id ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          memory_id = arguments[:memory_id] || arguments["memory_id"]
          title = arguments[:title] || arguments["title"]
          content = arguments[:content] || arguments["content"]
          tags = arguments[:tags] || arguments["tags"]
          change_reason = arguments[:change_reason] || arguments["change_reason"] || "Updated via AI tool"

          if memory_id.blank?
            return { success: false, error: "memory_id is required" }
          end

          space = context[:space]
          memory = space.memories.find_by(id: memory_id)

          unless memory
            return {
              success: false,
              error: "Memory not found with ID: #{memory_id}"
            }
          end

          updater = context[:advisor] || context[:user]

          # Build update attributes (only update provided fields)
          update_attrs = {}
          update_attrs[:title] = title if title.present?
          update_attrs[:content] = content if content.present?

          # Handle tags in metadata
          if tags.present?
            current_metadata = memory.metadata || {}
            update_attrs[:metadata] = current_metadata.merge("tags" => Array(tags))
          end

          if update_attrs.empty?
            return {
              success: false,
              error: "No fields to update. Provide title, content, or tags."
            }
          end

          # Add updater after checking for empty (updater alone doesn't count as an update)
          update_attrs[:updated_by] = updater

          # Create version record before updating
          memory.create_version!(
            created_by: updater,
            change_reason: change_reason
          )

          memory.update!(update_attrs)

          {
            success: true,
            memory_id: memory.id,
            title: memory.title,
            message: "Memory updated successfully",
            version_created: true,
            change_reason: change_reason
          }
        rescue ActiveRecord::RecordInvalid => e
          {
            success: false,
            error: "Failed to update memory: #{e.message}"
          }
        end
      end
    end
  end
end
