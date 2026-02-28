class ConversationParticipant < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account, optional: true
  belongs_to :conversation
  belongs_to :advisor

  enum :role, {
    advisor: "advisor",
    scribe: "scribe"
  }, default: "advisor"

  validates :conversation, presence: true
  validates :advisor, presence: true
  validates :role, presence: true
  validates :advisor_id, uniqueness: { scope: :conversation_id, message: "is already a participant in this conversation" }

  # Default scope excludes scribe for regular advisor listings
  scope :advisors_only, -> { where(role: "advisor") }
  scope :scribes_only, -> { where(role: "scribe") }
  scope :ordered, -> { order(:position, :created_at) }

  before_validation :set_account_from_conversation, on: :create

  private

  def set_account_from_conversation
    self.account_id ||= conversation.account_id if conversation
  end
end
