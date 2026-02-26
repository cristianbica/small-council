module RubyLLMTools
  class CreateMemoryTool < RubyLLM::Tool
    description "Creates a new memory entry in the space"

    param :title,
      desc: "The title of the memory (required)",
      type: :string,
      required: true

    param :content,
      desc: "The content/body of the memory in markdown format (required)",
      type: :string,
      required: true

    param :memory_type,
      desc: "Type of memory: summary, knowledge, conversation_summary, or conversation_notes (default: knowledge)",
      type: :string,
      required: false

    def execute(title:, content:, memory_type: "knowledge")
      # Get context from the chat context (set by controller)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      memory = Memory.create!(
        account: context[:space].account,
        space: context[:space],
        title: title,
        content: content,
        memory_type: valid_memory_type(memory_type),
        status: "active",
        created_by: context[:user],
        updated_by: context[:user]
      )

      {
        success: true,
        message: "Created memory ##{memory.id}: #{memory.title}",
        memory_id: memory.id,
        memory_type: memory.memory_type
      }
    rescue => e
      { error: "Failed to create memory: #{e.message}" }
    end

    private

    def valid_memory_type(type)
      return type if Memory::MEMORY_TYPES.include?(type)
      "knowledge"
    end
  end
end
