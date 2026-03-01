class Advisor < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :space, optional: true
  belongs_to :llm_model, optional: true

  has_many :council_advisors, dependent: :destroy
  has_many :councils, through: :council_advisors
  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants
  has_many :messages, as: :sender, dependent: :restrict_with_error

  # Encrypt sensitive fields at rest
  encrypts :system_prompt
  encrypts :short_description

  validates :name, presence: true
  validates :account, presence: true

  # Advisors need system_prompt but llm_model is optional (defaults to account default)
  validates :system_prompt, presence: true, unless: :is_scribe?
  validate :llm_model_belongs_to_account, if: -> { llm_model_id.present? }

  # Check if this is the Scribe advisor (using is_scribe flag)
  def scribe?
    is_scribe
  end

  # Get the effective LLM model for this advisor
  # Returns the advisor's specific model, or falls back to account default
  def effective_llm_model
    llm_model || account.default_llm_model || account.llm_models.enabled.first
  end

  # Check if this advisor has a valid LLM model (either specific or default)
  def llm_model_configured?
    return true if is_scribe?  # Scribe uses special handling
    effective_llm_model.present?
  end

  # Delegation to effective_llm_model for convenience
  delegate :provider, :provider_type, to: :effective_llm_model, allow_nil: true

  private

  # Validate that if llm_model_id is provided, it belongs to the account
  def llm_model_belongs_to_account
    return unless llm_model_id.present?
    return unless account.present?
    return if account.llm_models.exists?(id: llm_model_id)

    errors.add(:llm_model, "must belong to this account")
  end
end
