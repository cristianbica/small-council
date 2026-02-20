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

  scope :enabled, -> { where(enabled: true, deprecated: false).where(deleted_at: nil) }
  scope :available, -> { enabled }
  scope :deprecated, -> { where(deprecated: true) }
  scope :soft_deleted, -> { where.not(deleted_at: nil) }

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

  # Returns LLM::Client scoped to this model
  # (all operations available including chat)
  def api
    @api ||= LLM::Client.new(provider: provider, model: self)
  end

  # Sync metadata from ruby_llm
  def sync_from_ruby_llm!
    model_info = api.info
    return unless model_info

    update!(
      metadata: {
        capabilities: {
          chat: model_info.type == "chat",
          vision: model_info.supports_vision?,
          json_mode: model_info.structured_output?,
          functions: model_info.supports_functions?
        },
        pricing: {
          input_price_per_million: model_info.input_price_per_million,
          output_price_per_million: model_info.output_price_per_million
        },
        context_window: model_info.context_window,
        max_tokens: model_info.max_tokens
      }
    )
  end

  # Capability checkers
  def supports_chat?
    metadata.dig("capabilities", "chat") || false
  end

  def supports_vision?
    metadata.dig("capabilities", "vision") || false
  end

  def supports_json_mode?
    metadata.dig("capabilities", "json_mode") || false
  end

  def supports_functions?
    metadata.dig("capabilities", "functions") || false
  end

  # Pricing accessors
  def input_price_per_million
    metadata.dig("pricing", "input_price_per_million")
  end

  def output_price_per_million
    metadata.dig("pricing", "output_price_per_million")
  end

  # Context window accessor
  def context_window
    metadata["context_window"]
  end

  def max_tokens
    metadata["max_tokens"]
  end
end
