class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user_agent, :ip_address
  attribute :account

  delegate :user, to: :session, allow_nil: true
end
