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

  # Soft delete
  def soft_delete
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Full API identifier (provider-specific format)
  def full_identifier
    "#{provider.provider_type}/#{identifier}"
  end

  # Display name with provider
  def display_name
    "#{name} (#{provider.name})"
  end

  # Capability checkers (use capabilities column, fallback to metadata for flexibility)
  def supports_chat?
    capabilities["chat"] || metadata.dig("capabilities", "chat") || type == "chat"
  end

  def supports_vision?
    capabilities["vision"] || metadata.dig("vision") || false
  end

  def supports_json_mode?
    capabilities["json_mode"] || metadata.dig("structured_output") || false
  end

  def supports_functions?
    capabilities["functions"] || metadata.dig("supports_functions") || false
  end

  def supports_streaming?
    capabilities["streaming"] || metadata.dig("streaming") || false
  end

  # Pricing accessors (use metadata as source of truth)
  def input_price
    metadata.dig("pricing", "input").to_f
  end

  def output_price
    metadata.dig("pricing", "output").to_f
  end
end
