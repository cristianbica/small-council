class Council < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :user

  has_many :council_advisors, dependent: :destroy
  has_many :advisors, through: :council_advisors
  has_many :conversations, dependent: :destroy

  enum :visibility, {
    private_visibility: "private",
    shared: "shared"
  }, default: "private", prefix: true

  validates :name, presence: true
  validates :account, presence: true
  validates :user, presence: true
end
