class Account < ApplicationRecord
  # acts_as_tenant will be added when gem is installed
  # This is the root tenant model

  has_many :users, dependent: :destroy
  has_many :advisors, dependent: :destroy
  has_many :councils, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :usage_records, dependent: :destroy

  accepts_nested_attributes_for :users, limit: 1

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  # Scope for global advisors that can be shared across accounts
  scope :with_global_advisors, -> { joins(:advisors).where(advisors: { global: true }) }
end
