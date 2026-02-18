class Advisor < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :council, optional: true

  has_many :council_advisors, dependent: :destroy
  has_many :councils, through: :council_advisors
  has_many :messages, as: :sender, dependent: :destroy

  enum :model_provider, {
    openai: "openai",
    anthropic: "anthropic",
    gemini: "gemini"
  }

  validates :name, presence: true
  validates :account, presence: true

  # Simple advisors (with council_id) only need name and short_description
  # Full advisors (without council_id) need all AI model fields
  validates :system_prompt, presence: true, unless: -> { council_id.present? }
  validates :model_provider, presence: true, unless: -> { council_id.present? }
  validates :model_id, presence: true, unless: -> { council_id.present? }

  scope :global, -> { where(global: true) }
  scope :custom, -> { where(global: false) }

  # Helper method for simple advisors
  def simple?
    council_id.present?
  end
end
