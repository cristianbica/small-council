class AiClient
  class Error < StandardError; end
  class ApiError < Error; end
  class RateLimitError < Error; end
  class InvalidResponseError < Error; end

  MAX_RETRIES = 2
  RETRY_DELAY = 1 # seconds
  MAX_MEMORY_LENGTH = 2000 # characters to keep context manageable

  attr_reader :advisor, :conversation, :message

  def initialize(advisor:, conversation:, message:)
    @advisor = advisor
    @conversation = conversation
    @message = message
  end

  # Main entry point: calls LLM API and returns response content
  def generate_response
    model = advisor.effective_llm_model
    return nil unless model.present?
    return nil unless model.enabled?

    with_retries do
      # Build enhanced system prompt with context and tool instructions
      system_prompt = build_enhanced_system_prompt_with_tools

      # Build messages and space memory context
      messages = build_messages
      memory_context = build_memory_context

      # Store prompt data in the message before API call (only if persisted)
      if message.persisted?
        message.update!(
          prompt_text: system_prompt,
          debug_data: {
            request: {
              model: model.identifier,
              temperature: advisor.model_config["temperature"] || 0.7,
              max_tokens: advisor.model_config["max_tokens"] || 1000,
              provider: model.provider.provider_type,
              messages_count: messages.length,
              memory_included: memory_context.present?,
              memory_context_length: memory_context&.length || 0,
              council_context_included: system_prompt.include?("council"),
              conversation_context_included: system_prompt.include?("Current Conversation"),
              tools_enabled: true,
              tools_count: ScribeToolExecutor.available_tools(for_scribe: false).count
            }
          }
        )
      end

      # Configure RubyLLM with the advisor's provider
      context = RubyLLM.context do |config|
        case model.provider.provider_type
        when "openai"
          config.openai_api_key = model.provider.api_key
          config.openai_organization_id = model.provider.organization_id
        when "openrouter"
          config.openrouter_api_key = model.provider.api_key
        end
      end

      # Create chat with advisor tools
      chat = context.chat(model: model.identifier).with_tools(
        RubyLLMTools::AdvisorQueryMemoriesTool,
        RubyLLMTools::AdvisorQueryConversationsTool,
        RubyLLMTools::AdvisorReadConversationTool,
        RubyLLMTools::AdvisorAskAdvisorTool
      )

      # Add system instructions
      chat.with_instructions(system_prompt)

      # Add memory context as first message if available
      if memory_context.present?
        chat.add_message(role: "system", content: memory_context)
      end

      # Add conversation history
      messages.each do |msg|
        chat.add_message(role: msg[:role], content: msg[:content])
      end

      # Set up tool execution context via Thread.current (tools access this)
      tool_context = ToolExecutionContext.new(
        conversation: conversation,
        space: conversation.council&.space,
        advisor: advisor,
        user: conversation.user
      )
      Thread.current[:advisor_tool_context] = tool_context

      begin
        # Execute chat and get response
        response = chat.complete

        # Handle any tool calls
        tool_results = handle_tool_calls(response, chat)

        # Update message with response debug data (only if persisted)
        if message.persisted? && message.debug_data.present?
          message.debug_data["response"] = {
            input_tokens: response.input_tokens,
            output_tokens: response.output_tokens,
            model_used: response.model_id,
            timestamp: Time.current.iso8601,
            tool_calls: response.tool_calls&.map { |tc| { name: tc.name, params: tc.params } } || [],
            tool_results: tool_results
          }
          message.save!
        end

        {
          content: response.content,
          input_tokens: response.input_tokens,
          output_tokens: response.output_tokens,
          total_tokens: response.input_tokens.to_i + response.output_tokens.to_i,
          model: response.model_id,
          provider: model.provider.provider_type,
          tool_calls: response.tool_calls || [],
          tool_results: tool_results
        }
      ensure
        Thread.current[:advisor_tool_context] = nil
      end
    end
  rescue LLM::APIError => e
    log_error(e)
    raise ApiError, "AI API call failed: #{e.message}"
  rescue => e
    log_error(e)
    raise ApiError, "Unexpected error: #{e.message}"
  end

  private

  # Build enhanced system prompt with council and space context
  def build_enhanced_system_prompt
    base_prompt = advisor.system_prompt

    # Add council context
    council_context = build_council_context

    # Add advisor differentiation context
    expertise_context = build_expertise_context

    # Combine prompts
    parts = [ base_prompt ]
    parts << council_context if council_context.present?
    parts << expertise_context if expertise_context.present?

    parts.join("\n\n---\n\n")
  end

  # Build council context section
  def build_council_context
    council = conversation.council
    return nil unless council

    context_parts = []

    # Council name and description
    context_parts << "You are participating in the '#{council.name}' council."

    if council.description.present?
      context_parts << "Council purpose: #{council.description}"
    end

    # Add info about other advisors in the council with their expertise
    other_advisors = council.advisors.where.not(id: advisor.id)
    if other_advisors.any?
      context_parts << "Other advisors in this council:"
      other_advisors.each do |other|
        expertise = other.short_description.presence || "Advisor"
        context_parts << "  - #{other.name}: #{expertise}"
      end
    end

    # Add current conversation context
    current_context = build_current_conversation_context
    context_parts << current_context if current_context.present?

    # Add Rules of Engagement context
    roe = conversation.rules_of_engagement
    context_parts << "Engagement mode: #{roe.humanize}"

    case roe
    when "moderated"
      context_parts << "The Scribe is coordinating this discussion. Wait for direction."
    when "round_robin"
      context_parts << "Advisors take turns responding. Be concise and add value."
    when "on_demand"
      context_parts << "Respond when mentioned or when you have relevant expertise to contribute."
    when "consensus"
      context_parts << "Work toward agreement with other advisors. Build on others' points, acknowledge agreements and disagreements, and help converge on shared understanding."
    when "silent"
      context_parts << "You are observing silently. No response needed unless specifically asked."
    end

    context_parts.join("\n")
  end

  # Build expertise context - what makes this advisor unique
  def build_expertise_context
    context_parts = []

    context_parts << "YOUR ROLE IN THIS COUNCIL:"

    # Use short_description to highlight expertise
    if advisor.short_description.present?
      context_parts << "Your expertise: #{advisor.short_description}"
    end

    # Add differentiation guidance based on RoE
    roe = conversation.rules_of_engagement
    case roe
    when "consensus"
      context_parts << "In consensus mode, focus on:"
      context_parts << "- Offering your unique perspective based on your expertise"
      context_parts << "- Building on points made by other advisors"
      context_parts << "- Identifying areas of agreement and bridging gaps"
      context_parts << "- Adding value rather than repeating what others have said"
    when "round_robin"
      context_parts << "In round robin mode, wait your turn and provide a focused, valuable contribution."
    end

    context_parts.join("\n")
  end

  # Build context about the current conversation (not yet resolved)
  def build_current_conversation_context
    return nil if conversation.messages.count <= 1 # Only the initial message

    context_parts = []
    context_parts << "## Current Conversation Summary"

    # Count messages by role
    user_messages = conversation.messages.where(role: "user").count
    advisor_messages = conversation.messages.where(role: "advisor").where.not(id: message.id).count

    context_parts << "This conversation has #{user_messages} user message(s) and #{advisor_messages} advisor response(s)."

    # Get the last significant message (what triggered this response)
    last_message = conversation.messages.where.not(id: message.id).order(created_at: :desc).first
    if last_message.present?
      sender_name = case last_message.sender_type
      when "User" then "the user"
      when "Advisor" then last_message.sender&.name || "another advisor"
      else "someone"
      end

      context_parts << ""
      context_parts << "**Most recent message (from #{sender_name}):**"
      # Truncate if too long
      content = last_message.content
      if content.length > 300
        content = content[0...300] + "..."
      end
      context_parts << "\"#{content}\""

      # If it's from another advisor, note what they said
      if last_message.sender_type == "Advisor" && last_message.sender_id != advisor.id
        context_parts << ""
        context_parts << "Consider: How does your perspective differ from or complement what #{last_message.sender&.name || 'the other advisor'} just said?"
      end
    end

    # Add conversation title if helpful
    if conversation.title.present?
      context_parts << ""
      context_parts << "Topic: #{conversation.title}"
    end

    context_parts.join("\n")
  end

  # Build space memory context from the memories table
  # ONLY the 'summary' memory type is auto-fed to AI agents
  # Other memory types (conversation_summary, conversation_notes, knowledge)
  # must be queried on-demand via the query_memories tool
  def build_memory_context
    space = conversation.council&.space
    return nil unless space

    context_parts = []

    # Add the PRIMARY SUMMARY memory (ONLY this type is auto-fed)
    summary_memory = Memory.primary_summary_for(space)
    if summary_memory
      context_parts << "## Space Knowledge & Decisions"
      context_parts << "The following is the accumulated knowledge and key decisions for this space:"
      context_parts << ""
      summary_text = summary_memory.content.length > MAX_MEMORY_LENGTH ?
        summary_memory.content[0...MAX_MEMORY_LENGTH] + "...\n[Additional memory truncated for brevity]" :
        summary_memory.content
      context_parts << summary_text
    end

    # Note: We intentionally do NOT auto-feed:
    # - conversation_summary memories (too specific, query on-demand)
    # - conversation_notes memories (too verbose, query on-demand)
    # - knowledge memories (query on-demand when relevant)
    # Advisors can use the query_memories tool to access these

    # Add current conversation memory/draft if available (existing behavior)
    if conversation.memory.present? || conversation.draft_memory.present?
      context_parts << ""
      context_parts << "## This Conversation's Context"

      if conversation.draft_memory.present?
        context_parts << "Draft summary of this conversation so far:"
        draft_text = conversation.draft_memory.length > 500 ?
          conversation.draft_memory[0...500] + "..." :
          conversation.draft_memory
        context_parts << draft_text
      elsif conversation.memory.present?
        context_parts << "Resolved conversation summary:"
        memory_text = conversation.memory.length > 500 ?
          conversation.memory[0...500] + "..." :
          conversation.memory
        context_parts << memory_text
      end
    end

    # Join all parts and truncate if too long
    full_context = context_parts.join("\n")

    if full_context.length > MAX_MEMORY_LENGTH
      full_context = full_context[0...MAX_MEMORY_LENGTH] + "\n\n[Additional context truncated for brevity]"
    end

    full_context.presence
  end

  def build_messages
    conversation.messages.chronological.filter_map do |msg|
      next if msg.id == message.id # Skip the pending message itself

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      { role: role, content: msg.content }
    end
  end

  def with_retries
    retries = 0
    begin
      yield
    rescue StandardError => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(RETRY_DELAY * retries)
        retry
      else
        raise
      end
    end
  end

  def log_error(error)
    Rails.logger.error "[AiClient] Error for advisor #{advisor.id}: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n") if error.backtrace
  end

  # Handle tool calls from the LLM response
  def handle_tool_calls(response, chat)
    return [] unless response.tool_calls&.any?

    results = []

    response.tool_calls.each do |tool_call|
      tool_name = tool_call.name
      tool_params = tool_call.params

      Rails.logger.info "[AiClient] Tool call: #{tool_name} with params: #{tool_params}"

      begin
        # Create execution context
        context = ToolExecutionContext.new(
          conversation: conversation,
          space: conversation.council&.space,
          advisor: advisor,
          user: conversation.user
        )

        # Execute the tool via ScribeToolExecutor
        result = ScribeToolExecutor.execute_and_format(
          tool_name: tool_name,
          params: tool_params,
          context: context,
          for_scribe: false
        )

        results << {
          tool: tool_name,
          params: tool_params,
          result: result
        }

        # Add tool result back to the conversation for potential follow-up
        if result.is_a?(Hash) && result[:success]
          chat.add_message(
            role: "tool",
            content: result[:message] || "Tool executed successfully",
            tool_call_id: tool_call.id
          )
        else
          error_msg = result.is_a?(Hash) ? result[:error] : "Tool execution failed"
          chat.add_message(
            role: "tool",
            content: "Error: #{error_msg}",
            tool_call_id: tool_call.id
          )
        end
      rescue => e
        Rails.logger.error "[AiClient] Tool execution error: #{e.message}"
        results << {
          tool: tool_name,
          params: tool_params,
          error: e.message
        }

        chat.add_message(
          role: "tool",
          content: "Error: #{e.message}",
          tool_call_id: tool_call.id
        )
      end
    end

    results
  end

  # Build enhanced system prompt with tool instructions
  def build_enhanced_system_prompt_with_tools
    base_prompt = build_enhanced_system_prompt

    # Add tool instructions
    tool_instructions = build_tool_instructions

    [ base_prompt, tool_instructions ].compact.join("\n\n---\n\n")
  end

  # Build tool usage instructions for advisors
  def build_tool_instructions
    tools = ScribeToolExecutor.available_tools(for_scribe: false)

    parts = []
    parts << "## Available Tools"
    parts << "You have access to the following tools:"
    parts << ""

    tools.each do |tool_class|
      tool = tool_class.new
      parts << "- **#{tool.name}**: #{tool.description}"
    end

    parts << ""
    parts << "## When to Use Tools"
    parts << "- Use **query_memories** when you need additional context beyond the auto-fed summary"
    parts << "- Use **query_conversations** to find past discussions on specific topics"
    parts << "- Use **read_conversation** to get full details from a specific conversation ID"
    parts << "- Use **ask_advisor** to communicate with other advisors in the council"
    parts << ""
    parts << "## Tool Usage Guidelines"
    parts << "1. Tools are optional - only use them when you need additional information"
    parts << "2. After using ask_advisor, the other advisor will respond separately in a conversation"
    parts << "3. Do not simulate advisor responses - always use ask_advisor to let them respond"
    parts << "4. You can use multiple tools in sequence if needed"

    parts.join("\n")
  end
end
