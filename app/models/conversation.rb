class Conversation < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :council, optional: true
  belongs_to :user

  has_many :messages, dependent: :destroy
  has_many :conversation_participants, dependent: :destroy
  has_many :advisors, through: :conversation_participants

  # Encrypt memory fields at rest (stored in *_ciphertext columns)
  encrypts :memory
  encrypts :draft_memory

  enum :status, {
    active: "active",
    concluding: "concluding",
    resolved: "resolved",
    archived: "archived"
  }, default: "active"

  enum :conversation_type, {
    council_meeting: "council_meeting",
    adhoc: "adhoc"
  }, default: "council_meeting"

  # New simplified RoE types
  enum :roe_type, {
    open: "open",
    consensus: "consensus",
    brainstorming: "brainstorming"
  }, default: "open"

  validates :account, presence: true
  validates :user, presence: true
  validates :title, presence: true
  validate :must_have_at_least_one_advisor, on: :update

  # Custom validation to check for advisors (skip on create to allow building participants)
  # The validation on :update ensures conversations eventually have advisors
  def must_have_at_least_one_advisor
    # Check both persisted participants and those in memory
    total_advisors = conversation_participants.to_a.count { |p| p.advisor.present? && !p.advisor.scribe? }

    if total_advisors < 1
      errors.add(:advisors, "must have at least one advisor")
    end
  end

  # Council is required for council_meeting type
  validates :council, presence: true, if: -> { council_meeting? }

  scope :recent, -> { order(last_message_at: :desc) }
  scope :active, -> { where(status: "active") }
  scope :adhoc_conversations, -> { where(conversation_type: "adhoc") }
  scope :council_meetings, -> { where(conversation_type: "council_meeting") }

  # Returns the scribe participant for this conversation
  def scribe_participant
    conversation_participants.find_by(role: "scribe")
  end

  # Returns the scribe advisor for this conversation
  def scribe_advisor
    scribe_participant&.advisor
  end

  # Check if conversation has a scribe
  def has_scribe?
    scribe_participant.present?
  end

  # Ensure scribe is present in conversation (called after creation)
  def ensure_scribe_present!
    return if has_scribe?

    # Find scribe from account
    scribe = account.advisors.find_by(is_scribe: true)
    return unless scribe

    conversation_participants.create!(
      advisor: scribe,
      role: "scribe",
      position: 0
    )
  end

  # Add an advisor to the conversation
  def add_advisor(advisor)
    return false if advisors.include?(advisor)
    return false if advisor.is_scribe?  # Scribe is auto-added

    conversation_participants.create!(
      advisor: advisor,
      role: "advisor",
      position: conversation_participants.maximum(:position).to_i + 1
    )
  end

  # Returns non-scribe participants
  def advisor_participants
    conversation_participants.where(role: "advisor").order(:position)
  end

  # Returns non-scribe advisors
  def participant_advisors
    advisor_participants.map(&:advisor)
  end

  # Returns all participant advisors including scribe
  def all_participant_advisors
    conversation_participants.ordered.map(&:advisor)
  end

  # Get max depth for this conversation based on RoE
  def max_depth
    case roe_type
    when "open"
      1
    when "consensus", "brainstorming"
      2
    else
      1
    end
  end

  # Legacy methods for backward compatibility
  def last_advisor_id
    context["last_advisor_id"]
  end

  def mark_advisor_spoken(advisor_id)
    update_column(:context, context.merge("last_advisor_id" => advisor_id))
  end

  def advisor_has_responded?(advisor_id)
    context["responded_advisor_ids"]&.include?(advisor_id.to_s)
  end

  def mark_advisor_responded(advisor_id)
    responded = context["responded_advisor_ids"] || []
    update_column(:context, context.merge("responded_advisor_ids" => (responded + [ advisor_id.to_s ]).uniq))
  end

  def all_advisors_responded?
    responded = context["responded_advisor_ids"] || []
    participant_advisors.count == responded.count
  end

  def clear_responded_advisors
    update_column(:context, context.except("responded_advisor_ids"))
  end

  def increment_scribe_initiated_count!
    increment!(:scribe_initiated_count)
  end

  def reset_scribe_initiated_count!
    update_column(:scribe_initiated_count, 0)
  end

  # Parsed memory data
  def memory_data
    mem = memory
    return {} if mem.blank?

    mem.is_a?(String) ? JSON.parse(mem) : mem
  rescue JSON::ParserError
    {}
  end
end
