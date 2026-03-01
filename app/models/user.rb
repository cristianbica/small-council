class User < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account

  has_many :councils, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :messages, as: :sender, dependent: :destroy
  has_many :sessions, dependent: :destroy

  has_secure_password

  # Token support for password reset and email verification
  generates_token_for :password_reset, expires_in: 20.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_verification, expires_in: 24.hours do
    email
  end

  enum :role, {
    member: "member",
    admin: "admin"
  }, default: "member"

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :account, presence: true

  def display_name
    "user"
  end
end
