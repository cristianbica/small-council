class GenerateConversationSummaryJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation&.concluding?

    # Set tenant context for background job
    ActsAsTenant.current_tenant = conversation.account

    # Build conversation transcript
    transcript = build_transcript(conversation)

    # Generate summary
    summary = generate_summary(transcript)

    # Store draft summary
    conversation.update!(
      context: conversation.context.merge("draft_memory" => summary.to_json)
    )

    # Notify user via Turbo Stream that summary is ready for review
    broadcast_summary_ready(conversation)
  ensure
    ActsAsTenant.current_tenant = nil
  end

  private

  def build_transcript(conversation)
    conversation.messages.chronological.map do |msg|
      sender_name = msg.sender.is_a?(User) ? msg.sender.email : msg.sender.name
      "#{sender_name}: #{msg.content}"
    end.join("\n\n")
  end

  def generate_summary(transcript)
    # For now, simple placeholder
    # Future: Call AI to generate structured summary
    {
      key_decisions: "- TBD\n",
      action_items: "- TBD\n",
      insights: "- TBD\n",
      raw_summary: "Summary of #{transcript.length} characters"
    }
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
