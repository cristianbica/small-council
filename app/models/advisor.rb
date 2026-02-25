class Advisor < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :space
  belongs_to :llm_model, optional: true

  has_many :council_advisors, dependent: :destroy
  has_many :councils, through: :council_advisors
  has_many :messages, as: :sender, dependent: :destroy

  # Encrypt sensitive fields at rest
  encrypts :system_prompt
  encrypts :short_description

  validates :name, presence: true
  validates :account, presence: true
  validates :space, presence: true

  # Advisors need system_prompt and llm_model unless they're simple (legacy check removed)
  validates :system_prompt, presence: true
  validates :llm_model, presence: true

  scope :global, -> { where(global: true) }
  scope :custom, -> { where(global: false) }
  scope :for_space, ->(space) { where(space: space) }

  # Check if this is the Scribe advisor
  def scribe?
    name.downcase.include?("scribe") || name.downcase.include?("scrib")
  end

  # Delegation to llm_model for convenience
  delegate :provider, :provider_type, to: :llm_model, allow_nil: true
end
