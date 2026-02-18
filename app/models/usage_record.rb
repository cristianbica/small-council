class UsageRecord < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :message, optional: true

  validates :account, presence: true
  validates :provider, presence: true
  validates :model, presence: true
  validates :input_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :by_model, ->(model) { where(model: model) }
  scope :recorded_since, ->(time) { where("recorded_at >= ?", time) }
  scope :recorded_before, ->(time) { where("recorded_at < ?", time) }

  # Helper to calculate total tokens
  def total_tokens
    input_tokens + output_tokens
  end

  # Helper to format cost as dollars
  def cost_dollars
    cost_cents / 100.0
  end
end
