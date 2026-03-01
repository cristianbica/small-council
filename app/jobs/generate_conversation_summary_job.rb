class GenerateConversationSummaryJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation&.concluding?

    # Store conversation as instance variable for use in other methods
    @conversation = conversation

    # Set tenant context for background job
    ActsAsTenant.current_tenant = conversation.account

    # Build conversation transcript
    transcript = build_transcript

    # Generate summary
    summary = generate_summary(transcript)

    # Store draft summary (encrypted at rest) - still needed for review UI
    @conversation.update!(draft_memory: summary.to_json)

    # ALSO create a memory entry for this conversation
    create_conversation_memory(summary)

    # Notify user via Turbo Stream that summary is ready for review
    broadcast_summary_ready(@conversation)
  ensure
    ActsAsTenant.current_tenant = nil
  end

  private

  def build_transcript
    @conversation.messages.chronological.filter_map do |msg|
      # Skip placeholder/pending messages
      next if msg.pending?
      # Skip regular advisor "is thinking..." placeholders, but keep Scribe "selecting an advisor" messages
      next if msg.content&.include?("is thinking...") && !msg.sender.try(:scribe?)

      sender_name = msg.sender.is_a?(User) ? msg.sender.email : msg.sender.name
      "#{sender_name}: #{msg.content}"
    end.join("\n\n")
  end

  def generate_summary(transcript)
    generator = AI::ContentGenerator.new
    content = generator.generate_conversation_summary(
      conversation: @conversation,
      style: :structured
    )

    parse_structured_summary(content)
  rescue AI::ContentGenerator::NoModelError => e
    Rails.logger.error "[GenerateConversationSummaryJob] No AI model available: #{e.message}"
    {
      key_decisions: "- [No AI model available - please configure an LLM model or enable an existing one]\n",
      action_items: "- [No AI model available]\n",
      insights: "- [No AI model available]\n",
      open_questions: "- [No AI model available]\n",
      raw_summary: "Summary generation failed: No LLM model available or model is disabled.\n\nPlease go to AI Providers and configure a model.\n\nTranscript length: #{transcript.length} characters"
    }
  rescue => e
    Rails.logger.error "[GenerateConversationSummaryJob] AI summary failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    # Fallback to template structure
    {
      key_decisions: "- [AI generation failed - please fill in manually]\n",
      action_items: "- [AI generation failed - please fill in manually]\n",
      insights: "- [AI generation failed - please fill in manually]\n",
      open_questions: "- [AI generation failed - please fill in manually]\n",
      raw_summary: "Summary generation failed: #{e.message}\n\nPlease fill in the structured fields manually.\n\nTranscript length: #{transcript.length} characters"
    }
  end

  def parse_structured_summary(content)
    sections = {
      key_decisions: extract_section(content, "Key Decisions"),
      action_items: extract_section(content, "Action Items"),
      insights: extract_section(content, "Insights"),
      open_questions: extract_section(content, "Open Questions"),
      raw_summary: content
    }

    # Ensure each section has at least a placeholder if empty
    sections.each do |key, value|
      if value.blank? && key != :raw_summary
        sections[key] = "- None identified\n"
      end
    end

    sections
  end

  def extract_section(content, section_name)
    # Match section header in multiple formats:
    # - ## Key Decisions
    # - **Key Decisions:**
    # - **Key Decisions**
    # - Key Decisions:
    # Use negative lookahead to stop at any other section header or end

    # Escape the section name for regex
    escaped_name = Regexp.escape(section_name)

    # Pattern matches: optional ## or **, optional whitespace, section name, optional : and **, optional \n
    # Then captures everything until the next section header or end
    # Section headers can be: ## or ** prefixed, or plain text followed by colon
    pattern = /(?:##?|\*\*)?\s*#{escaped_name}\s*:?\*?\s*\n?(.*?)(?=(?:\n\s*(?:##?|\*\*)?\s*(?:Key Decisions|Action Items|Insights|Open Questions)\s*:?\*?|\z))/mi

    match = content.match(pattern)

    if match
      Rails.logger.debug "[GenerateConversationSummaryJob#extract_section] Found '#{section_name}' - length: #{match[1].length}"
      match[1].strip
    else
      Rails.logger.debug "[GenerateConversationSummaryJob#extract_section] No match found for '#{section_name}'"
      ""
    end
  end

  def broadcast_summary_ready(conversation)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "conversation_status",
      partial: "conversations/summary_review",
      locals: { conversation: conversation }
    )
  end

  # Create a memory entry for this conversation
  # This is saved as conversation_summary type (NOT auto-fed to agents)
  def create_conversation_memory(summary)
    space = @conversation.council&.space
    return unless space

    # Build memory content from structured summary
    content = <<~CONTENT
      ## Key Decisions
      #{summary[:key_decisions]}

      ## Action Items
      #{summary[:action_items]}

      ## Insights
      #{summary[:insights]}

      ## Open Questions
      #{summary[:open_questions]}
    CONTENT

    # Find the Scribe advisor to use as creator
    scribe = find_scribe_advisor
    return unless scribe

    # Create the memory entry
    memory = Memory.create_conversation_summary!(
      conversation: @conversation,
      title: "Conversation: #{@conversation.title}",
      content: content,
      creator: scribe
    )

    Rails.logger.info "[GenerateConversationSummaryJob] Created conversation_summary memory #{memory.id} for conversation #{@conversation.id}"
  rescue => e
    Rails.logger.error "[GenerateConversationSummaryJob] Failed to create memory: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    # Don't raise - summary was already saved to draft_memory
  end

  def find_scribe_advisor
    # Scribe is always present - created by Space's after_create callback
    @conversation.scribe_advisor ||
      @conversation.account.advisors.find_by(is_scribe: true)
  end
end
