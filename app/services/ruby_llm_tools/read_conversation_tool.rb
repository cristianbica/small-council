module RubyLLMTools
  class ReadConversationTool < RubyLLM::Tool
    description "Read all messages from a specific conversation by ID"

    param :conversation_id,
      desc: "The ID number of the conversation to read",
      type: :integer

    def execute(conversation_id: nil)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      if conversation_id.nil?
        return { error: "conversation_id is required" }
      end

      conversation = context[:space].conversations.find_by(id: conversation_id)
      return { error: "Conversation ##{conversation_id} not found" } unless conversation

      messages = conversation.messages.chronological.map do |msg|
        sender_name = case msg.sender
        when User then msg.sender.email
        when Advisor then msg.sender.name
        else msg.sender_type
        end

        {
          sender: sender_name,
          role: msg.role,
          content: msg.content,
          created_at: msg.created_at.strftime("%Y-%m-%d %H:%M")
        }
      end

      {
        success: true,
        message: "Retrieved #{messages.size} messages from conversation ##{conversation.id}",
        conversation: {
          id: conversation.id,
          title: conversation.title,
          status: conversation.status,
          summary: conversation.memory
        },
        messages: messages
      }
    end
  end
end
