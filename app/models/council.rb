class Council < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :user
  belongs_to :space

  has_many :council_advisors, dependent: :destroy
  has_many :advisors, through: :council_advisors
  has_many :conversations, dependent: :destroy

  # Encrypt council memory at rest
  encrypts :memory

  enum :visibility, {
    private_visibility: "private",
    shared: "shared"
  }, default: "private", prefix: true

  validates :name, presence: true
  validates :account, presence: true
  validates :user, presence: true
  validates :space, presence: true

  # Get available advisors from the space (for council creation/editing)
  def available_advisors
    space.non_scribe_advisors
  end

  # Get the Scribe advisor from the space
  def scribe_advisor
    space.scribe_advisor
  end

  # Check if this council has the Scribe advisor assigned
  def has_scribe?
    advisors.any?(&:scribe?)
  end

  # Add Scribe advisor to this council if not already present
  def ensure_scribe_assigned
    scribe = scribe_advisor
    return unless scribe
    return if advisors.include?(scribe)

    council_advisors.create!(advisor: scribe)
  end

  # Create a new conversation with all council advisors as participants
  def create_conversation!(user:, title:, roe_type: :open, initial_message: nil)
    conversation = conversations.new(
      account: account,
      user: user,
      title: title,
      conversation_type: :council_meeting,
      roe_type: roe_type
    )

    conversation.save!

    # Add all council advisors as participants
    advisors.each do |advisor|
      role = advisor.scribe? ? "scribe" : "advisor"
      conversation.conversation_participants.create!(
        advisor: advisor,
        role: role,
        position: council_advisors.find_by(advisor: advisor)&.position || 0
      )
    end

    # Create initial message if provided
    if initial_message.present?
      conversation.messages.create!(
        account: account,
        sender: user,
        role: "user",
        content: initial_message
      )
    end

    conversation
  end
end
