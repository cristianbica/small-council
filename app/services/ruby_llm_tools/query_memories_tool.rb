module RubyLLMTools
  class QueryMemoriesTool < RubyLLM::Tool
    description "Search for memories in this space by keyword"

    param :query,
      desc: "Search term or keyword to find relevant memories",
      type: :string

    param :memory_type,
      desc: "Optional: filter by type (summary, knowledge, conversation_summary, conversation_notes)",
      type: :string

    param :limit,
      desc: "Maximum number of results to return (default: 5, max: 10)",
      type: :integer

    def execute(query: nil, memory_type: nil, limit: 5)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      if query.blank?
        return { error: "Query parameter is required" }
      end

      limit = [ limit.to_i, 10 ].min
      limit = 1 if limit < 1

      scope = context[:space].memories.active
      scope = scope.where(memory_type: memory_type) if memory_type.present? && Memory::MEMORY_TYPES.include?(memory_type)
      scope = scope.where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")

      memories = scope.recent.limit(limit)

      if memories.empty?
        return {
          success: true,
          message: "No memories found matching '#{query}'",
          memories: []
        }
      end

      {
        success: true,
        message: "Found #{memories.size} memory/ies matching '#{query}'",
        memories: memories.map do |m|
          {
            id: m.id,
            title: m.title,
            type: m.memory_type,
            preview: m.content.truncate(200),
            updated_at: m.updated_at.strftime("%Y-%m-%d %H:%M")
          }
        end
      }
    end
  end
end
