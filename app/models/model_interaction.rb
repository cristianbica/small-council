class ModelInteraction < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :message

  after_create_commit :broadcast_interaction_updates

  validates :account, presence: true
  validates :message, presence: true
  validates :sequence, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :request_payload, presence: true
  validates :interaction_type, presence: true, inclusion: { in: %w[chat tool] }

  scope :chronological, -> { order(sequence: :asc) }

  def total_tokens
    input_tokens + output_tokens
  end

  private

  def broadcast_interaction_updates
    stream = "conversation_#{message.conversation_id}"
    interactions = message.model_interactions.chronological

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "interactions-list-#{message_id}",
      partial: "messages/interactions_list",
      locals: { message: message, interactions: interactions }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "interactions-count-#{message_id}",
      partial: "messages/interactions_count",
      locals: { message: message, interactions: interactions }
    )
  rescue => e
    Rails.logger.error "[ModelInteraction] Failed to broadcast interaction update: #{e.message}"
  end
end
