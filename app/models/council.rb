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

  # Get the Scribe advisor from the space
  def scribe_advisor
    space.scribe_advisor
  end

  # Add Scribe advisor to this council if not already present
  def ensure_scribe_assigned
    scribe = scribe_advisor
    return unless scribe
    return if advisors.include?(scribe)

    council_advisors.create!(advisor: scribe)
  end
end
