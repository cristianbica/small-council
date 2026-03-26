class Advisor < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  SCRIBE_SYSTEM_PROMPT = <<~PROMPT
    Specific rules and context provided at chat time.

    You are the Scribe, an expert moderator and conversation analyst for this space.

    Generic scribe rules:
    - Monitor the conversation and help maintain balanced participation.
    - Summarize key discussion points and surface disagreements or open questions.
    - Suggest next steps or clarifying questions when they would move the conversation forward.
    - Help maintain focus and respect the conversation rules and depth limits.
    - Keep responses concise but substantive.
    - Do not include speaker labels or stage directions.
    - Ask the user whether they want to conclude when the discussion appears complete.
  PROMPT

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

  before_validation :normalize_name

  validates :name, presence: true
  validates :name, format: {
    with: NAME_FORMAT,
    message: "must contain only lowercase letters, numbers, and single dashes"
  }
  validates :name, uniqueness: { scope: :space_id, case_sensitive: false }
  validates :account, presence: true

  # Advisors need system_prompt but llm_model is optional (defaults to account default)
  validates :system_prompt, presence: true, unless: :is_scribe?
  validate :llm_model_belongs_to_account, if: -> { llm_model_id.present? }

  scope :scribes, -> { where(is_scribe: true) }
  scope :non_scribes, -> { where(is_scribe: false) }

  def self.update_all_scribes_prompt
    Advisor.scribes.update_all system_prompt: Advisor::SCRIBE_SYSTEM_PROMPT
  end

  # Check if this is the Scribe advisor (using is_scribe flag)
  def scribe?
    is_scribe
  end

  def non_scribe?
    !is_scribe
  end

  def display_name
    name
  end

  def role
    scribe? ? :scribe : :advisor
  end

  # Get the effective LLM model for this advisor
  # Returns the advisor's specific model, or falls back to account default
  def effective_llm_model
    llm_model || account.default_llm_model || account.llm_models.enabled.first
  end

  # Delegation to effective_llm_model for convenience
  delegate :provider, :provider_type, to: :effective_llm_model, allow_nil: true

  private

  def normalize_name
    return if name.nil?

    self.name = name.to_s
      .downcase
      .gsub(/[^a-z0-9-]+/, "-")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
  end

  # Validate that if llm_model_id is provided, it belongs to the account
  def llm_model_belongs_to_account
    return unless llm_model_id.present?
    return unless account.present?
    return if account.llm_models.exists?(id: llm_model_id)

    errors.add(:llm_model, "must belong to this account")
  end
end
