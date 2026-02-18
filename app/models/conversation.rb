class Conversation < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :council
  belongs_to :user

  has_many :messages, dependent: :destroy

  enum :status, {
    active: "active",
    concluding: "concluding",
    resolved: "resolved",
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

  # Track which advisors have responded (for auto-conclusion)
  def advisor_has_responded?(advisor_id)
    context["responded_advisor_ids"]&.include?(advisor_id.to_s)
  end

  def mark_advisor_responded(advisor_id)
    responded = context["responded_advisor_ids"] || []
    update_column(:context, context.merge("responded_advisor_ids" => (responded + [ advisor_id.to_s ]).uniq))
  end

  def all_advisors_responded?
    responded = context["responded_advisor_ids"] || []
    council.advisors.count == responded.count
  end

  def clear_responded_advisors
    update_column(:context, context.except("responded_advisor_ids"))
  end

  # Access the draft memory from context
  def draft_memory
    context["draft_memory"]
  end

  # Access the approved memory from context
  def memory
    context["memory"]
  end

  # Parsed memory data (returns hash)
  def memory_data
    memory = context["memory"]
    return {} if memory.blank?

    memory.is_a?(String) ? JSON.parse(memory) : memory
  rescue JSON::ParserError
    {}
  end
end
