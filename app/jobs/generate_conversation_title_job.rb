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

    title = AI::ContentGenerator.new.generate_conversation_title(
      conversation: conversation,
      first_message_content: first_message.content
    )
    return if title.blank?

    title = title.to_s.squish.first(255)
    return if title.blank?

    Conversation.where(id: conversation.id, title_locked: false).update_all(title: title, updated_at: Time.current)
  rescue AI::ContentGenerator::NoModelError => e
    Rails.logger.warn "[GenerateConversationTitleJob] No model available for conversation #{conversation_id}: #{e.message}"
  rescue AI::ContentGenerator::GenerationError => e
    Rails.logger.warn "[GenerateConversationTitleJob] Title generation failed for conversation #{conversation_id}: #{e.message}"
  rescue => e
    Rails.logger.error "[GenerateConversationTitleJob] Unexpected error for conversation #{conversation_id}: #{e.message}"
  ensure
    ActsAsTenant.current_tenant = nil
  end
end
