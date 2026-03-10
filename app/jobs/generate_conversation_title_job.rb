class GenerateConversationTitleJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, first_message_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation&.adhoc?
    return if conversation.title_locked?

    first_message = conversation.messages.find_by(id: first_message_id, role: "user", sender_type: "User")
    return unless first_message

    first_user_message_id = conversation.messages.where(role: "user", sender_type: "User").order(:created_at, :id).limit(1).pick(:id)
    return unless first_user_message_id == first_message.id

    ActsAsTenant.current_tenant = conversation.account

    result = AI.generate_text(
      prompt: "tasks/conversation_title",
      description: first_message.content,
      space: conversation.space,
      account: conversation.account,
      async: false
    )
    title = result&.content
    return if title.blank?

    title = title.to_s.squish.first(255)
    return if title.blank?

    Conversation.where(id: conversation.id, title_locked: false).update_all(title: title, updated_at: Time.current)
  rescue AI::ResolutionError => e
    Rails.logger.warn "[GenerateConversationTitleJob] Title generation setup failed for conversation #{conversation_id}: #{e.message}"
  rescue AI::Client::Error => e
    Rails.logger.warn "[GenerateConversationTitleJob] Title generation failed for conversation #{conversation_id}: #{e.message}"
  rescue => e
    Rails.logger.error "[GenerateConversationTitleJob] Unexpected error for conversation #{conversation_id}: #{e.message}"
  ensure
    ActsAsTenant.current_tenant = nil
  end
end
