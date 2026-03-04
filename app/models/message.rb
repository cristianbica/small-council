class Message < ApplicationRecord
  HANDLE_MENTION_REGEX = /(?:^|[^a-z0-9_])@([a-z0-9]+(?:-[a-z0-9]+)*)(?![a-z0-9_])/i
  ALL_MENTION_REGEX = /(?:^|[^a-z0-9_])@(all|everyone)(?![a-z0-9_])/i

  def self.extract_mentions(text)
    return [] if text.blank?

    text.scan(HANDLE_MENTION_REGEX).flatten
  end

  acts_as_tenant :account
  belongs_to :account
  belongs_to :conversation
  belongs_to :sender, polymorphic: true

  # Message threading
  belongs_to :parent_message, class_name: "Message", foreign_key: "in_reply_to_id", optional: true
  has_many :replies, class_name: "Message", foreign_key: "in_reply_to_id", dependent: :nullify

  has_one :usage_record, dependent: :destroy
  has_many :model_interactions, dependent: :destroy

  # Encrypt message content and prompt at rest
  encrypts :content
  encrypts :prompt_text

  enum :role, {
    user: "user",
    advisor: "advisor",
    system: "system"
  }

  enum :status, {
    pending: "pending",
    responding: "responding",
    complete: "complete",
    error: "error",
    cancelled: "cancelled"
  }, default: "complete"

  validates :account, presence: true
  validates :conversation, presence: true
  validates :sender, presence: true
  validates :role, presence: true
  validates :content, presence: true

  scope :chronological, -> { order(created_at: :asc) }
  scope :root_messages, -> { where(in_reply_to_id: nil) }
  scope :solved, -> { where(pending_advisor_ids: []) }

  # Check if message has been solved (all pending advisors responded)
  def solved?
    pending_advisor_ids.blank? || pending_advisor_ids.empty?
  end

  # Check if this message is pending responses from specific advisors
  def pending_for?(advisor_id)
    pending_advisor_ids&.include?(advisor_id.to_s) || pending_advisor_ids&.include?(advisor_id)
  end

  # Remove an advisor from pending list
  def resolve_for_advisor!(advisor_id)
    current_pending = pending_advisor_ids || []
    updated_pending = current_pending.reject { |id| id.to_s == advisor_id.to_s }
    update!(pending_advisor_ids: updated_pending)
  end

  # Calculate the depth of this message in the reply chain
  def depth
    current_depth = 0
    current = self
    while current.parent_message
      current_depth += 1
      current = current.parent_message
    end
    current_depth
  end

  # Check if this is a root message (not a reply)
  def root_message?
    in_reply_to_id.nil?
  end

  # Check if this message is a command
  def command?
    content&.start_with?("/")
  end

  # Get thread messages (this message + all replies recursively)
  def thread_messages
    result = [ self ]
    replies.each do |reply|
      result += reply.thread_messages
    end
    result
  end

  # Parse @mentions from content
  def mentions
    self.class.extract_mentions(content)
  end

  # Check if content mentions @all or @everyone
  def mentions_all?
    content&.match?(ALL_MENTION_REGEX)
  end
end
