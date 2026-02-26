class ScribeChatMessage < ApplicationRecord
  belongs_to :space
  belongs_to :user

  # Encrypt content at rest
  encrypts :content

  # Validations
  validates :space, presence: true
  validates :user, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant system tool] }
  validates :content, presence: true

  # Scopes
  scope :for_space_and_user, ->(space, user) { where(space: space, user: user) }
  scope :recent, -> { order(created_at: :asc) }
  scope :last_n, ->(n) { recent.limit(n) }

  # Get conversation history formatted for RubyLLM
  def self.to_conversation_history(space, user, limit: 20)
    messages = for_space_and_user(space, user).recent.limit(limit)

    messages.map do |msg|
      case msg.role
      when "user"
        { role: "user", content: msg.content }
      when "assistant"
        { role: "assistant", content: msg.content }
      when "system"
        { role: "system", content: msg.content }
      else
        { role: "user", content: msg.content }
      end
    end
  end
end
