class Space < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  has_many :councils, dependent: :destroy
  has_many :conversations, through: :councils

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :account, presence: true
end
