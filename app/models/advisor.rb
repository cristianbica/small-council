class Advisor < ApplicationRecord
  # acts_as_tenant :account will be enabled when gem is installed
  belongs_to :account

  has_many :council_advisors, dependent: :destroy
  has_many :councils, through: :council_advisors
  has_many :messages, as: :sender, dependent: :destroy

  enum :model_provider, {
    openai: "openai",
    anthropic: "anthropic",
    gemini: "gemini"
  }

  validates :name, presence: true
  validates :system_prompt, presence: true
  validates :model_provider, presence: true
  validates :model_id, presence: true
  validates :account, presence: true

  scope :global, -> { where(global: true) }
  scope :custom, -> { where(global: false) }
end
