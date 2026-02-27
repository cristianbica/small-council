module RubyLLMTools
  class AdvisorReadConversationTool < RubyLLM::Tool
    description "Read all messages from a specific conversation by ID. Returns the conversation title, status, summary, and all messages with sender information. Use this after finding a conversation with query_conversations to get the full details."

    param :conversation_id,
      desc: "The ID of the conversation to read (e.g., '123', 'abc-456')",
      type: :string,
      required: true

    def execute(conversation_id:)
      context = Thread.current[:advisor_tool_context]
      return { error: "No context available" } unless context

      tool = AdvisorTools::ReadConversationTool.new
      params = { "conversation_id" => conversation_id }

      result = tool.execute(params, context)

      if result[:success]
        { success: true, message: result[:message], data: result[:data] }
      else
        { error: result[:message] }
      end
    rescue => e
      Rails.logger.error "[AdvisorReadConversationTool] Error: #{e.message}"
      { error: "Failed to read conversation: #{e.message}" }
    end
  end
end
