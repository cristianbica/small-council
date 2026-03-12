class Space < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  has_many :councils, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :advisors, dependent: :destroy
  has_many :memories, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :account, presence: true

  after_create :create_scribe_advisor

  # Find or create the Scribe advisor for this space
  def scribe_advisor
    scribe = advisors.find_by(is_scribe: true)
    return scribe if scribe.present?
    create_scribe_advisor
  end

  # Get all non-Scribe advisors in this space
  def non_scribe_advisors
    advisors.where(is_scribe: false)
  end

  private

  def create_scribe_advisor
    # Check if scribe already exists to avoid duplicate creation
    existing_scribe = advisors.find_by(is_scribe: true)
    return existing_scribe if existing_scribe.present?

    advisors.create!(
      name: "scribe",
      system_prompt: Advisor::SCRIBE_SYSTEM_PROMPT,
      llm_model: account.default_llm_model || account.llm_models.enabled.first,
      global: false,
      is_scribe: true
    )
  rescue => e
    Rails.logger.error "[Space] Failed to create Scribe advisor: #{e.message}"
    # Don't prevent space creation if Scribe creation fails
    nil
  end
end
