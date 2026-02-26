module RubyLLMTools
  class RestoreMemoryVersionTool < RubyLLM::Tool
    description "Restores a memory to a previous version. Use this when a memory was incorrectly modified by an LLM or when you need to revert to an earlier state. Creates a new version tracking the restore operation."

    param :memory_id,
      desc: "The ID of the memory to restore (required)",
      type: :integer

    param :version_number,
      desc: "The version number to restore to (required). Use list_memory_versions to find available version numbers.",
      type: :integer

    param :reason,
      desc: "Optional reason for restoring this version (e.g., 'LLM made incorrect changes', 'Reverting to accurate information')",
      type: :string

    def execute(memory_id: nil, version_number: nil, reason: nil)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      if memory_id.blank?
        return { error: "Memory ID is required" }
      end

      if version_number.blank?
        return { error: "Version number is required" }
      end

      memory = context[:space].memories.active.find_by(id: memory_id)

      unless memory
        return {
          error: "Memory ##{memory_id} not found in this space",
          hint: "Use query_memories to find the correct memory ID"
        }
      end

      version = memory.versions.find_by(version_number: version_number)

      unless version
        available_versions = memory.versions.pluck(:version_number)
        return {
          error: "Version ##{version_number} not found for memory ##{memory_id}",
          available_versions: available_versions,
          hint: "Use list_memory_versions to see all available versions"
        }
      end

      # Store current state before restore for the message
      current_version = memory.latest_version&.version_number || 1

      # Perform the restore
      begin
        new_version = version.restore_to_memory!(
          context[:user],
          reason.presence || "Restored by user request"
        )

        {
          success: true,
          message: "Restored memory ##{memory.id} (#{memory.title}) to version #{version_number}",
          data: {
            memory_id: memory.id,
            memory_title: memory.title,
            restored_to_version: version_number,
            previous_version: current_version,
            new_version_created: new_version&.version_number,
            restore_reason: reason.presence || "Restored by user request",
            restored_content_preview: version.content.truncate(200)
          }
        }
      rescue => e
        Rails.logger.error "[RestoreMemoryVersionTool] Error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        {
          error: "Failed to restore memory: #{e.message}"
        }
      end
    rescue => e
      Rails.logger.error "[RestoreMemoryVersionTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      {
        error: "An error occurred while restoring: #{e.message}"
      }
    end
  end
end
