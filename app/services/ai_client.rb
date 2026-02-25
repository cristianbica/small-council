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
    return nil unless advisor.llm_model.present?
    return nil unless advisor.llm_model.enabled?

    with_retries do
      # Build enhanced system prompt with context
      system_prompt = build_enhanced_system_prompt

      # Build messages and space memory context
      messages = build_messages
      memory_context = build_memory_context

      # Store prompt data in the message before API call (only if persisted)
      if message.persisted?
        message.update!(
          prompt_text: system_prompt,
          debug_data: {
            request: {
              model: advisor.llm_model.identifier,
              temperature: advisor.model_config["temperature"] || 0.7,
              max_tokens: advisor.model_config["max_tokens"] || 1000,
              provider: advisor.llm_model.provider.provider_type,
              messages_count: messages.length,
              memory_included: memory_context.present?
            }
          }
        )
      end

      # Prepend memory context as a system message if available
      full_messages = []
      if memory_context.present?
        full_messages << { role: "system", content: memory_context }
      end
      full_messages.concat(messages)

      # Use the new unified client: model_instance.api.chat(...)
      result = advisor.llm_model.api.chat(
        full_messages,
        system_prompt: system_prompt,
        temperature: advisor.model_config["temperature"] || 0.7,
        max_tokens: advisor.model_config["max_tokens"] || 1000
      )

      # Update message with response debug data (only if persisted)
      if message.persisted? && message.debug_data.present?
        message.debug_data["response"] = {
          input_tokens: result[:input_tokens],
          output_tokens: result[:output_tokens],
          model_used: result[:model],
          timestamp: Time.current.iso8601
        }
        message.save!
      end

      result
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

    # Combine prompts
    if council_context.present?
      <<~PROMPT.strip
        #{base_prompt}

        ---

        #{council_context}
      PROMPT
    else
      base_prompt
    end
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

    # Add info about other advisors in the council
    other_advisors = council.advisors.where.not(id: advisor.id)
    if other_advisors.any?
      advisor_names = other_advisors.map(&:name).join(", ")
      context_parts << "Other advisors in this council: #{advisor_names}"
    end

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
      context_parts << "Work toward agreement with other advisors. Acknowledge points of consensus and disagreement."
    when "silent"
      context_parts << "You are observing silently. No response needed unless specifically asked."
    end

    context_parts.join("\n")
  end

  # Build space memory context from resolved conversations
  def build_memory_context
    space = conversation.council&.space
    return nil unless space

    context_parts = []

    # Add space memory if available
    if space.memory.present?
      context_parts << "## Organizational Memory (Previous Decisions & Insights)"
      # Truncate to keep prompt manageable
      memory_text = space.memory.length > MAX_MEMORY_LENGTH ?
        space.memory[0...MAX_MEMORY_LENGTH] + "...\n[Additional memory truncated for brevity]" :
        space.memory
      context_parts << memory_text
    end

    # Add recent resolved conversations from this council
    recent_conversations = space.conversations
      .where(council: conversation.council)
      .where(status: :resolved)
      .where.not(id: conversation.id)
      .where.not(memory: nil)
      .order(updated_at: :desc)
      .limit(3)

    if recent_conversations.any?
      context_parts << "## Recent Resolved Conversations in This Council"

      recent_conversations.each do |conv|
        context_parts << "### #{conv.title || 'Untitled Conversation'}"

        if conv.memory_data.present?
          memory_data = conv.memory_data

          if memory_data["key_decisions"].present?
            context_parts << "Key Decisions: #{memory_data["key_decisions"].truncate(200)}"
          end

          if memory_data["action_items"].present?
            context_parts << "Action Items: #{memory_data["action_items"].truncate(200)}"
          end

          if memory_data["insights"].present?
            context_parts << "Insights: #{memory_data["insights"].truncate(200)}"
          end
        end

        context_parts << "" # Empty line between conversations
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
end
