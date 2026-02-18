class Message < ApplicationRecord
  # acts_as_tenant :account will be enabled when gem is installed
  belongs_to :account
  belongs_to :conversation
  belongs_to :sender, polymorphic: true

  has_one :usage_record, dependent: :destroy

  enum :role, {
    user: "user",
    advisor: "advisor",
    system: "system"
  }

  enum :status, {
    pending: "pending",
    complete: "complete",
    error: "error"
  }, default: "complete"

  validates :account, presence: true
  validates :conversation, presence: true
  validates :sender, presence: true
  validates :role, presence: true

  scope :by_role, ->(role) { where(role: role) }
  scope :chronological, -> { order(created_at: :asc) }
end
