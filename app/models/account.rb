class Account < ApplicationRecord
  # acts_as_tenant will be added when gem is installed
  # This is the root tenant model

  has_many :users, dependent: :destroy
  has_many :spaces, dependent: :destroy
  has_many :advisors, dependent: :destroy
  has_many :councils, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :providers, dependent: :destroy
  has_many :llm_models, dependent: :destroy
  belongs_to :default_llm_model, class_name: "LLMModel", optional: true

  accepts_nested_attributes_for :users, limit: 1

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :default_llm_model_belongs_to_account, on: :update
  validate :default_llm_model_is_enabled, on: :update

  # Scope for global advisors that can be shared across accounts
  scope :with_global_advisors, -> { joins(:advisors).where(advisors: { global: true }) }

  private

  def default_llm_model_belongs_to_account
    return unless default_llm_model_id.present?
    return if llm_models.exists?(id: default_llm_model_id)

    errors.add(:default_llm_model, "must belong to this account")
  end

  def default_llm_model_is_enabled
    return unless default_llm_model.present?
    return if default_llm_model.enabled?

    errors.add(:default_llm_model, "must be enabled")
  end
end
