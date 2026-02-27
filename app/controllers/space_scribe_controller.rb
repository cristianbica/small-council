# Controller for the Scribe chat interface
# Provides a dedicated chat UI for interacting with the Scribe advisor
# outside of regular conversations
class SpaceScribeController < ApplicationController
  before_action :set_space
  before_action :set_scribe_advisor

  # GET /spaces/:space_id/scribe
  def show
    # Load recent memories for the sidebar browser
    @memories = @space.memories
                       .active
                       .recent
                       .limit(10)

    # Get memory types for filtering
    @memory_types = Memory::MEMORY_TYPES

    # Get recent conversations from this space
    @recent_conversations = @space.conversations
                                   .where(status: :resolved)
                                   .recent
                                   .limit(5)

    # Load chat history for this user
    @chat_history = ScribeChatMessage
                    .for_space_and_user(@space, Current.user)
                    .recent
                    .limit(50)
  end

  # POST /spaces/:space_id/scribe/chat
  # Handles chat messages from user to Scribe
  def chat
    message_content = params[:message].to_s.strip

    if message_content.blank?
      render json: { error: "Message cannot be blank" }, status: :unprocessable_entity
      return
    end

    begin
      # Get the effective LLM model for the scribe
      scribe_model = @scribe.effective_llm_model

      unless scribe_model.present?
        render json: { error: "No LLM model configured. Please set up an AI provider first." }, status: :unprocessable_entity
        return
      end

      # Build conversation history
      conversation_history = ScribeChatMessage.to_conversation_history(@space, Current.user, limit: 20)
      messages = conversation_history.map do |msg|
        { role: msg[:role], content: msg[:content] }
      end
      messages << { role: "user", content: message_content }

      # Create AI client with tools
      client = AI::Client.new(
        model: scribe_model,
        system_prompt: build_chat_system_prompt_with_tools,
        tools: [
          AI::Tools::Internal::CreateMemoryTool.new,
          AI::Tools::Internal::UpdateMemoryTool.new,
          AI::Tools::Internal::ListMemoriesTool.new,
          AI::Tools::Internal::QueryMemoriesTool.new,
          AI::Tools::Internal::ListConversationsTool.new,
          AI::Tools::Internal::QueryConversationsTool.new,
          AI::Tools::Internal::ReadConversationTool.new,
          AI::Tools::External::BrowseWebTool.new,
          AI::Tools::Conversations::AskAdvisorTool.new
        ]
      )

      # Build context for tools
      context = {
        space: @space,
        user: Current.user,
        advisor: @scribe
      }

      # Get response from AI
      response = client.chat(messages: messages, context: context)

      # Store the conversation in the database
      ScribeChatMessage.create!(
        space: @space,
        user: Current.user,
        role: "user",
        content: message_content
      )

      ScribeChatMessage.create!(
        space: @space,
        user: Current.user,
        role: "assistant",
        content: response.content,
        metadata: { tool_calls: response.tool_calls&.map(&:to_h) || [] }
      )

      render json: {
        message: response.content,
        tool_calls: response.tool_calls&.map(&:to_h) || []
      }
    rescue => e
      Rails.logger.error "[SpaceScribeController#chat] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      render json: {
        error: "Failed to generate response: #{e.message}"
      }, status: :internal_server_error
    end
  end

  # POST /spaces/:space_id/scribe/execute_tool
  # Executes a tool suggested by the Scribe
  def execute_tool
    tool_name = params[:tool_name]
    tool_params = params[:params] || {}

    context = ToolExecutionContext.new(
      conversation: nil,
      space: @space,
      advisor: @scribe,
      user: Current.user
    )

    result = ScribeToolExecutor.execute_and_format(
      tool_name: tool_name,
      params: tool_params,
      context: context,
      for_scribe: true
    )

    render json: result
  rescue ScribeToolExecutor::ToolNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue ScribeToolExecutor::ToolValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue => e
    render json: { error: "Tool execution failed: #{e.message}" }, status: :internal_server_error
  end

  # GET /spaces/:space_id/scribe/suggest
  # Returns quick action suggestions for the user
  def suggest
    suggestions = [
      {
        id: "summarize_recent",
        label: "Summarize recent conversations",
        description: "Create a summary of recent discussions",
        icon: "document-text"
      },
      {
        id: "find_decisions",
        label: "Find key decisions",
        description: "Search for important decisions made",
        icon: "check-circle"
      },
      {
        id: "create_knowledge",
        label: "Create knowledge entry",
        description: "Add a new knowledge memory",
        icon: "book-open"
      },
      {
        id: "review_memory",
        label: "Review space memory",
        description: "Overview of what the space knows",
        icon: "eye"
      }
    ]

    render json: { suggestions: suggestions }
  end

  private

  def set_space
    @space = Current.account.spaces.find(params[:space_id])
  end

  def set_scribe_advisor
    @scribe = @space.find_or_create_scribe_advisor

    unless @scribe
      redirect_to space_councils_path(@space), alert: "Could not initialize Scribe advisor."
    end
  end

  # Build system prompt with tool instructions
  def build_chat_system_prompt_with_tools
    memory_context = build_memory_context_for_chat
    recent_conversations = build_conversation_context
    advisors_list = build_advisors_context

    <<~PROMPT
      You are the Scribe, an expert assistant for managing space knowledge and memories.

      ## Your Capabilities
      You have access to tools that let you:
      - create_memory: Create a new memory with title, content, and type
      - update_memory: Update an existing memory
      - query_memories: Search existing memories by keyword
      - query_conversations: Find past conversations by topic
      - read_conversation: Read all messages from a specific conversation
      - browse_web: Fetch and read web pages
      - ask_advisor: Ask a question to a specific advisor in the council

      ## When to Use Tools
      - When a user asks you to "create a memory" or "save this" → use create_memory
      - When a user asks "what do we know about X?" → use query_memories
      - When a user asks "what did we discuss about Y?" → use query_conversations, then read_conversation
      - When a user gives you a conversation ID → use read_conversation
      - When a user asks you to "ask [advisor]" or "get feedback from [advisor]" → use ask_advisor

      ## Asking Advisors (CRITICAL - READ CAREFULLY)
      When the user asks you to "ask [advisor]", "get feedback from advisors", or similar:

      YOU MUST use the ask_advisor tool. DO NOT generate advisor responses yourself.

      CRITICAL RULES:
      1. You are the SCRIBE - you manage knowledge, you DO NOT speak for other advisors
      2. You CANNOT and SHOULD NOT simulate what other advisors would say
      3. When asked to gather feedback, ALWAYS use the ask_advisor tool
      4. Never say "Here's what the Systems Architect would say" - that's wrong
      5. Instead say "I'll ask Systems Architect and they'll respond in a conversation"

      CORRECT WORKFLOW:
      1. User: "Ask Systems Architect about using Docker"
      2. You: Use ask_advisor tool with advisor_name="Systems Architect", question="What do you think about using Docker?"
      3. You tell user: "I've asked Systems Architect. They'll respond in conversation #123."
      4. The REAL Systems Architect (AI agent) generates their own response separately

      WRONG (DO NOT DO THIS):
      - Simulating: "Systems Architect says: You should use Docker because..."
      - This is you pretending to be them, which defeats the purpose

      Advisor responses happen asynchronously in separate conversations.

      ## Available Advisors
      #{advisors_list}

      ## Current Context
      #{memory_context}

      #{recent_conversations}

      ## Guidelines
      1. Be helpful and proactive - use tools when they would help answer the user
      2. After creating a memory, confirm it was created and mention its ID
      3. When searching, summarize what you found in natural language
      4. Memory types: summary (auto-fed to AI), knowledge, conversation_summary, conversation_notes
      5. When asking advisors, ALWAYS use the ask_advisor tool. NEVER simulate their responses.
      6. You are the Scribe - you manage knowledge. Other advisors give specialized advice. Don't blur these roles.
    PROMPT
  end

  def build_conversation_context
    conversations = @space.conversations.resolved.recent.limit(5)
    return "" if conversations.empty?

    parts = [ "## Recent Conversations" ]
    conversations.each do |c|
      parts << "- ##{c.id}: #{c.title} (#{c.messages.count} messages)"
    end
    parts.join("\n")
  end

  def build_memory_context_for_chat
    parts = []

    # Include the primary summary if available
    summary = Memory.primary_summary_for(@space)
    if summary
      parts << "## Primary Space Summary"
      parts << summary.content.truncate(1000)
    end

    # Include memory counts
    memory_counts = @space.memories.active.group(:memory_type).count
    if memory_counts.any?
      parts << "\n## Memory Inventory"
      memory_counts.each do |type, count|
        parts << "- #{type.humanize}: #{count} memories"
      end
    end

    parts.join("\n")
  end

  def build_advisors_context
    advisors = @space.advisors.where.not(id: @scribe.id) # Exclude self
    return "No other advisors available in this space." if advisors.empty?

    parts = [ "Other advisors available in this space (use ask_advisor tool to communicate with them):" ]
    advisors.each do |advisor|
      desc = advisor.short_description.present? ? " - #{advisor.short_description}" : ""
      parts << "- #{advisor.name}#{desc}"
    end
    parts.join("\n")
  end
end
