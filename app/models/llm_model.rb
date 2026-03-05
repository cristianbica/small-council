class LLMModel < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :provider

  has_many :advisors, dependent: :nullify

  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: { scope: :provider_id }
  validates :provider, presence: true

  # Delegations for convenience
  delegate :provider_type, to: :provider, allow_nil: true

  # Scopes
  scope :enabled, -> { where(enabled: true, deprecated: false).where(deleted_at: nil) }
  scope :free, -> { where(free: true) }

  def display_name
    "#{name} (#{provider.name})"
  end

  # Pricing accessors (use metadata as source of truth)
  def input_price
    metadata.dig("pricing", "input").to_f
  end

  def output_price
    metadata.dig("pricing", "output").to_f
  end
end
