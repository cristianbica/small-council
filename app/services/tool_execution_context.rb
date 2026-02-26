# Context object passed to tools during execution
# Provides access to conversation, space, advisor, user, and utility methods
class ToolExecutionContext
  attr_reader :conversation, :space, :advisor, :user, :request_id

  def initialize(conversation:, space:, advisor:, user:, request_id: nil)
    @conversation = conversation
    @space = space
    @advisor = advisor
    @user = user
    @request_id = request_id || SecureRandom.uuid
  end

  # Helper to get account from conversation or space
  def account
    conversation&.account || space&.account
  end

  # Helper to get council from conversation
  def council
    conversation&.council
  end

  # Helper to get all messages in conversation
  def messages
    conversation&.messages&.chronological || []
  end

  # Helper to broadcast a message via Turbo Streams
  def broadcast_message(content, target: nil)
    return unless conversation

    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{conversation.id}",
      target: target || "messages",
      partial: "messages/message",
      locals: {
        message: OpenStruct.new(
          id: "tool_#{request_id}",
          content: content,
          sender: advisor,
          role: "system",
          created_at: Time.current
        ),
        current_user: user
      }
    )
  end

  # Helper to create a memory entry
  def create_memory(title:, content:, memory_type:, status: "active")
    return unless space

    Memory.create!(
      account: account,
      space: space,
      title: title,
      content: content,
      memory_type: memory_type,
      status: status,
      source: conversation,
      created_by: advisor,
      updated_by: advisor
    )
  end

  # Helper to query memories in the space
  def query_memories(query:, memory_type: nil, limit: 5)
    return [] unless space

    scope = space.memories.active
    scope = scope.by_type(memory_type) if memory_type.present?
    scope = scope.search(query)
    scope.recent.limit(limit)
  end

  # Helper to query conversations in the space
  def query_conversations(query:, limit: 5)
    return [] unless space

    conversations = space.conversations.recent.limit(20)

    # Simple text search
    conversations.select do |conv|
      searchable = [ conv.title, conv.memory ].compact.join(" ").downcase
      searchable.include?(query.downcase)
    end.first(limit)
  end

  # Helper to read a specific conversation
  def read_conversation(conversation_id)
    return nil unless space

    conversation = space.conversations.find_by(id: conversation_id)
    return nil unless conversation

    {
      conversation: conversation,
      messages: conversation.messages.chronological
    }
  end
end
