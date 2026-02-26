module RubyLLMTools
  class ListMemoryVersionsTool < RubyLLM::Tool
    description "Lists all versions of a memory. Use this to see the version history before deciding which version to restore. Shows version numbers, when they were created, and what changed."

    param :memory_id,
      desc: "The ID of the memory to list versions for (required)",
      type: :integer

    param :limit,
      desc: "Maximum number of versions to return (default: 10, max: 20)",
      type: :integer

    def execute(memory_id: nil, limit: 10)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      if memory_id.blank?
        return { error: "Memory ID is required" }
      end

      memory = context[:space].memories.find_by(id: memory_id)

      unless memory
        return {
          error: "Memory ##{memory_id} not found in this space",
          hint: "Use query_memories to find the correct memory ID"
        }
      end

      limit = [ limit.to_i, 20 ].min
      limit = 1 if limit < 1

      versions = memory.versions.ordered.limit(limit)

      if versions.empty?
        return {
          success: true,
          message: "No versions found for memory ##{memory_id} (#{memory.title})",
          data: {
            memory_id: memory.id,
            memory_title: memory.title,
            versions: []
          }
        }
      end

      version_list = versions.map do |v|
        {
          version_number: v.version_number,
          title: v.title,
          memory_type: v.memory_type,
          created_at: v.created_at.strftime("%Y-%m-%d %H:%M"),
          created_by: v.created_by_display,
          change_reason: v.change_reason,
          content_preview: v.content.truncate(150)
        }
      end

      {
        success: true,
        message: "Found #{versions.count} version(s) for memory ##{memory.id} (#{memory.title})",
        data: {
          memory_id: memory.id,
          memory_title: memory.title,
          current_version: memory.latest_version&.version_number,
          total_versions: memory.versions.count,
          versions: version_list
        }
      }
    rescue => e
      Rails.logger.error "[ListMemoryVersionsTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      {
        error: "An error occurred while listing versions: #{e.message}"
      }
    end
  end
end
