class Message < ApplicationRecord
  HANDLE_MENTION_REGEX = /(?:^|[^a-z0-9_])@([a-z0-9]+(?:-[a-z0-9]+)*)(?![a-z0-9_])/i
  ALL_MENTION_REGEX = /(?:^|[^a-z0-9_])@(all|everyone)(?![a-z0-9_])/i

  def self.extract_mentions(text)
    return [] if text.blank?

    text.scan(HANDLE_MENTION_REGEX).flatten
  end

  acts_as_tenant :account
  belongs_to :account
  belongs_to :conversation, touch: true
  belongs_to :sender, polymorphic: true

  # Message threading
  belongs_to :parent_message, class_name: "Message", foreign_key: "in_reply_to_id", optional: true
  has_many :replies, class_name: "Message", foreign_key: "in_reply_to_id", dependent: :nullify

  has_one :usage_record, dependent: :destroy
  has_many :model_interactions, dependent: :destroy

  encrypts :content
  encrypts :prompt_text

  store_accessor :debug_data, :retry_count

  enum :role, {
    user: "user",
    advisor: "advisor",
    system: "system"
  }

  enum :message_type, {
    chat: "chat",
    compaction: "compaction"
  }, default: "chat"

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
  scope :visible_in_chat, -> { where.not(status: "pending") }
  scope :root_messages, -> { where(in_reply_to_id: nil) }
  scope :solved, -> { where(pending_advisor_ids: []) }
  scope :since_last_compaction, -> { where(id: complete.compaction.last&.id.to_i..) }

  after_create_commit -> { broadcast_chat if broadcastable_create? }
  after_update_commit -> { broadcast_chat if broadcastable_update? }

  # Check if message has been solved (all pending advisors responded)
  def solved?
    pending_advisor_ids.blank? || pending_advisor_ids.empty?
  end

  def from_scribe?
    sender_type == "Advisor" && sender.scribe?
  end

  def from_non_scribe_advisor?
    sender_type == "Advisor" && !sender.scribe?
  end

  def from_user?
    sender_type == "User"
  end

  # Remove an advisor from pending list
  def resolve_for_advisor!(advisor_id)
    current_pending = pending_advisor_ids || []
    updated_pending = current_pending.reject { |id| id.to_s == advisor_id.to_s }
    update!(pending_advisor_ids: updated_pending)
  end

  def retry_count
    super.to_i
  end

  def retry!(reset_retry_count: true)
    return false unless error?
    return false unless sender.is_a?(Advisor)

    self.retry_count = 0 if reset_retry_count
    update!(status: "responding", content: "...")
    add_to_parent_message
    AI.generate_advisor_response(advisor: sender, message: self, async: true)
    true
  end

  def add_to_parent_message
    return unless parent_message
    current_pending = parent_message.pending_advisor_ids || []
    return if current_pending.include?(sender_id.to_s)
    parent_message.update!(pending_advisor_ids: current_pending + [ sender_id.to_s ])
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

  def reply?
    parent_message.present?
  end

  # Get thread messages (this message + all replies recursively)
  def thread_messages
    result = [ self ]
    replies.each do |reply|
      result += reply.thread_messages
    end
    result
  end

  # Check if content mentions @all or @everyone
  def mentions_all?
    content&.match?(ALL_MENTION_REGEX)
  end

  def mentions
    self.class.extract_mentions(content)
  end

  def mentions?(advisor)
    advisor = advisor.name if advisor.is_a?(Advisor)
    mentions_all? || mentions.include?(advisor.to_s.downcase)
  end

  private

  def broadcastable_create?
    visible_in_chat?
  end

  def broadcastable_update?
    visible_in_chat? && (saved_change_to_status? || saved_change_to_content? || saved_change_to_prompt_text? || saved_change_to_debug_data?)
  end

  def visible_in_chat?
    !pending?
  end

  def broadcast_chat
    broadcast_append_later_to(
      "conversation_#{conversation_id}",
      target: "messages",
      partial: "conversations/message",
      locals: { message: self }
    )
  end
end
