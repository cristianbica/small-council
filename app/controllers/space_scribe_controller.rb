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
  end

  # POST /spaces/:space_id/scribe/chat
  # Handles chat messages from user to Scribe
  def chat
    message_content = params[:message].to_s.strip

    if message_content.blank?
      render json: { error: "Message cannot be blank" }, status: :unprocessable_entity
      return
    end

    # Set up context for tools (accessible via Thread.current)
    Thread.current[:scribe_context] = {
      space: @space,
      user: Current.user,
      advisor: @scribe
    }

    begin
      # Configure RubyLLM with the advisor's provider
      context = RubyLLM.context do |config|
        case @scribe.llm_model.provider.provider_type
        when "openai"
          config.openai_api_key = @scribe.llm_model.provider.api_key
          config.openai_organization_id = @scribe.llm_model.provider.organization_id
        when "openrouter"
          config.openrouter_api_key = @scribe.llm_model.provider.api_key
        end
      end

      # Create chat with tools
      chat = context.chat(model: @scribe.llm_model.identifier).with_tools(
        RubyLLMTools::CreateMemoryTool,
        RubyLLMTools::QueryMemoriesTool,
        RubyLLMTools::QueryConversationsTool,
        RubyLLMTools::ReadConversationTool
      )

      # Build system prompt with tool instructions
      system_prompt = build_chat_system_prompt_with_tools

      # Add system message
      chat.with_instructions(system_prompt)

      # Add user message and get response
      response = chat.ask(message_content)

      render json: {
        message: response.content,
        tool_calls: response.tool_calls || []
      }
    rescue => e
      Rails.logger.error "[SpaceScribeController#chat] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      render json: {
        error: "Failed to generate response: #{e.message}"
      }, status: :internal_server_error
    ensure
      Thread.current[:scribe_context] = nil
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

    <<~PROMPT
      You are the Scribe, an expert assistant for managing space knowledge and memories.

      ## Your Capabilities
      You have access to tools that let you:
      - create_memory: Create a new memory with title, content, and type
      - query_memories: Search existing memories by keyword
      - query_conversations: Find past conversations by topic
      - read_conversation: Read all messages from a specific conversation

      ## When to Use Tools
      - When a user asks you to "create a memory" or "save this" → use create_memory
      - When a user asks "what do we know about X?" → use query_memories
      - When a user asks "what did we discuss about Y?" → use query_conversations, then read_conversation
      - When a user gives you a conversation ID → use read_conversation

      ## Current Context
      #{memory_context}

      #{recent_conversations}

      ## Guidelines
      1. Be helpful and proactive - use tools when they would help answer the user
      2. After creating a memory, confirm it was created and mention its ID
      3. When searching, summarize what you found in natural language
      4. Memory types: summary (auto-fed to AI), knowledge, conversation_summary, conversation_notes
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
end
