class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_current_request_details
  before_action :authenticate
  before_action :set_current_tenant
  before_action :set_current_space

  helper_method :authenticated?

  private

  def authenticate
    if session_record = Session.find_by_id(cookies.signed[:session_token])
      Current.session = session_record
    else
      redirect_to sign_in_path
    end
  end

  def authenticated?
    Current.session.present?
  end

  def set_current_request_details
    Current.user_agent = request.user_agent
    Current.ip_address = request.ip
  end

  def set_current_tenant
    Current.account = Current.user&.account
    ActsAsTenant.current_tenant = Current.account
  end

  def set_current_space
    return unless Current.account

    Current.space = Current.account.spaces.find_by(id: session[:space_id]) if session[:space_id]
    Current.space ||= Current.account.spaces.first

    # Auto-create default space if none exists (for legacy accounts)
    Current.space ||= Current.account.spaces.create!(name: "General", description: "Default space for your councils")
  end

  # Shared helper for getting available advisors for invite
  def available_advisors_for_invite
    return [] unless @conversation&.active? && Current.space
    Current.space.non_scribe_advisors.where.not(id: @conversation.advisor_ids)
  end
end
