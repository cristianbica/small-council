class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user_agent, :ip_address
  attribute :account
  attribute :space
  attribute :version_whodunnit
  attribute :version_metadata

  delegate :user, to: :session, allow_nil: true

  def version_whodunnit
    super || user
  end
end
