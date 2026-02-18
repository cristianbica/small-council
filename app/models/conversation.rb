class Conversation < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :council
  belongs_to :user

  has_many :messages, dependent: :destroy

  enum :status, {
    active: "active",
    archived: "archived"
  }, default: "active"

  validates :account, presence: true
  validates :council, presence: true
  validates :user, presence: true

  scope :recent, -> { order(last_message_at: :desc) }
  scope :active, -> { where(status: "active") }
end
