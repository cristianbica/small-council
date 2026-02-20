class Provider < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account

  has_many :llm_models, dependent: :destroy

  enum :provider_type, {
    openai: "openai",
    openrouter: "openrouter"
  }, prefix: :type

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :provider_type, presence: true
  validates :account, presence: true

  # Encrypt credentials at rest
  encrypts :credentials

  scope :enabled, -> { where(enabled: true) }
  scope :by_type, ->(type) { where(provider_type: type) }

  # Get API key from encrypted credentials
  def api_key
    credentials&.dig("api_key")
  end

  def api_key=(value)
    self.credentials = (credentials || {}).merge("api_key" => value)
  end

  # Organization ID for OpenAI
  def organization_id
    credentials&.dig("organization_id")
  end

  def organization_id=(value)
    self.credentials = (credentials || {}).merge("organization_id" => value)
  end

  # Returns LLM::Client for provider-level operations
  # (list_models, test_connection - chat will fail without model)
  def api
    @api ||= LLM::Client.new(provider: self)
  end
end
