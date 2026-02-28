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
  scope :available, -> { enabled }
  scope :deprecated, -> { where(deprecated: true) }
  scope :soft_deleted, -> { where.not(deleted_at: nil) }
  scope :free, -> { where(free: true) }
  scope :paid, -> { where(free: false) }

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

  # Returns AI::Client scoped to this model
  # (all operations available including chat)
  def api
    @api ||= AI::Client.new(model: self, system_prompt: "")
  end

  # Sync metadata from ruby_llm - stores full RubyLLM::Model::Info data
  def sync_from_ruby_llm!
    model_info = api.info
    return unless model_info

    # Store full RubyLLM data in metadata
    full_metadata = model_info.as_json

    # Extract important attributes for direct querying
    # Determine if free: either explicitly marked or both input/output price are 0
    is_free = if full_metadata["pricing"].present?
                input_price = full_metadata["pricing"]["input"].to_f
                output_price = full_metadata["pricing"]["output"].to_f
                input_price == 0.0 && output_price == 0.0
    else
                false
    end

    update!(
      metadata: full_metadata,
      free: is_free,
      context_window: full_metadata["context_window"],
      capabilities: extract_capabilities(full_metadata)
    )
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

  private

  def extract_capabilities(full_metadata)
    {
      "chat" => full_metadata["type"] == "chat",
      "vision" => full_metadata["vision"] || false,
      "json_mode" => full_metadata["structured_output"] || false,
      "functions" => full_metadata["supports_functions"] || false,
      "streaming" => full_metadata["streaming"] || false
    }
  end
end
