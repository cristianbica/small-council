class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user_agent, :ip_address
  attribute :account
  attribute :space

  delegate :user, to: :session, allow_nil: true
end
