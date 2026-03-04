class Conversation < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :council, optional: true
  belongs_to :space
  belongs_to :user

  has_many :messages, dependent: :destroy
  has_many :conversation_participants, dependent: :destroy
  has_many :advisors, through: :conversation_participants

  # Encrypt memory fields at rest (stored in *_ciphertext columns)
  encrypts :memory
  encrypts :draft_memory

  enum :status, {
    active: "active",
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
  validates :space, presence: true
  validates :user, presence: true
  validates :title, presence: true

  before_validation :assign_space_from_council

  # Council is required for council_meeting type
  validates :council, presence: true, if: -> { council_meeting? }

  scope :recent, -> { order(last_message_at: :desc) }
  scope :active, -> { where(status: "active") }
  scope :adhoc_conversations, -> { where(conversation_type: "adhoc") }

  def deletable_by?(user)
    return false unless user

    user_id == user.id || council&.user_id == user.id
  end

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
    scribe = space&.scribe_advisor
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
    when "consensus"
      5
    when "brainstorming"
      2
    else
      1
    end
  end

  def assign_space_from_council
    return if space_id.present?
    return unless council

    self.space = council.space
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
