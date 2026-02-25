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

    # Store draft summary (encrypted at rest)
    @conversation.update!(draft_memory: summary.to_json)

    # Notify user via Turbo Stream that summary is ready for review
    broadcast_summary_ready(@conversation)
  ensure
    ActsAsTenant.current_tenant = nil
  end

  private

  def build_transcript
    @conversation.messages.chronological.map do |msg|
      sender_name = msg.sender.is_a?(User) ? msg.sender.email : msg.sender.name
      "#{sender_name}: #{msg.content}"
    end.join("\n\n")
  end

  def generate_summary(transcript)
    # Create a system advisor for summarization if one doesn't exist
    scribe = find_or_create_scribe_advisor

    client = AiClient.new(
      advisor: scribe,
      conversation: @conversation,
      message: build_summary_prompt(transcript)
    )

    result = client.generate_response

    # Handle case where result is nil (no LLM model or disabled)
    if result.nil?
      Rails.logger.error "[GenerateConversationSummaryJob] No result from AI - check LLM model configuration"
      return {
        key_decisions: "- [No AI model available - please configure an LLM model or enable an existing one]\n",
        action_items: "- [No AI model available]\n",
        insights: "- [No AI model available]\n",
        open_questions: "- [No AI model available]\n",
        raw_summary: "Summary generation failed: No LLM model available or model is disabled.\n\nPlease go to AI Providers and configure a model.\n\nTranscript length: #{transcript.length} characters"
      }
    end

    parse_structured_summary(result[:content])
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

  def find_or_create_scribe_advisor
    # Look for existing scribe advisor or create a temporary one
    advisor = @conversation.account.advisors.find_by(name: "Scribe")

    return advisor if advisor.present?

    # Use account's default LLM model or fall back to first enabled
    llm_model = @conversation.account.default_llm_model || @conversation.account.llm_models.enabled.first

    raise "No LLM model available. Please configure a default model or enable at least one model." unless llm_model

    @conversation.account.advisors.create!(
      name: "Scribe",
      system_prompt: <<~PROMPT,
        You are an expert conversation analyst and scribe. Your task is to analyze conversation transcripts and produce structured summaries.

        Extract the following from the conversation:
        1. Key Decisions - Any decisions made by the participants
        2. Action Items - Tasks, follow-ups, or commitments mentioned
        3. Insights - Important insights or conclusions reached
        4. Open Questions - Unresolved questions or areas needing further exploration

        Format your response as:
        ## Key Decisions
        - [decision 1]
        - [decision 2]

        ## Action Items
        - [action 1]
        - [action 2]

        ## Insights
        - [insight 1]
        - [insight 2]

        ## Open Questions
        - [question 1]
        - [question 2]
      PROMPT
      llm_model: llm_model,
      global: true
    )
  end

  def build_summary_prompt(transcript)
    # Create a message object for the prompt (won't be saved)
    Message.new(
      account: @conversation.account,
      content: <<~PROMPT,
        Please analyze the following conversation transcript and produce a structured summary:

        ---
        #{transcript}
        ---

        Provide a structured summary with these sections:
        1. Key Decisions made
        2. Action Items identified
        3. Important Insights
        4. Open Questions

        Use the format specified in your system prompt.
      PROMPT
      role: "user"
    )
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
    # Match section header and capture content until next section or end
    # Use negative lookahead to stop at any other section header
    pattern = /##?\s*#{Regexp.escape(section_name)}[:\s]*\n?(.*?)(?=\n##?\s*(?:Key Decisions|Action Items|Insights|Open Questions)[:\s]*|\z)/mi
    match = content.match(pattern)
    match ? match[1].strip : ""
  end

  def broadcast_summary_ready(conversation)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "conversation_status",
      partial: "conversations/summary_review",
      locals: { conversation: conversation }
    )
  end
end
