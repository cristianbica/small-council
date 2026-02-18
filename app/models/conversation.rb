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

  enum :rules_of_engagement, {
    round_robin: "round_robin",
    moderated: "moderated",
    on_demand: "on_demand",
    silent: "silent",
    consensus: "consensus"
  }, default: "round_robin"

  validates :account, presence: true
  validates :council, presence: true
  validates :user, presence: true
  validates :title, presence: true

  scope :recent, -> { order(last_message_at: :desc) }
  scope :active, -> { where(status: "active") }

  # Returns the ID of the last advisor who spoke (stored in context jsonb)
  def last_advisor_id
    context["last_advisor_id"]
  end

  # Updates context with the last advisor who spoke
  def mark_advisor_spoken(advisor_id)
    update_column(:context, context.merge("last_advisor_id" => advisor_id))
  end
end
