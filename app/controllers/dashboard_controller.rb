class DashboardController < ApplicationController
  skip_before_action :set_current_space

  def index
    # Check if account has any spaces (before auto-creation)
    if Current.account.spaces.count == 0
      # No spaces - show empty dashboard
      @councils = []
      @conversations = []
      return
    end

    # Set current space manually (without auto-creation)
    Current.space = Current.account.spaces.find_by(id: session[:space_id]) if session[:space_id]
    Current.space ||= Current.account.spaces.first

    # Redirect to the space's councils page
    if Current.space.present?
      redirect_to space_councils_path(Current.space)
    end
  end
end
