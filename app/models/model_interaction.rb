class ModelInteraction < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :message

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
end
