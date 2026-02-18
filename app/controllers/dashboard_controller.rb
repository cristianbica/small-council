class DashboardController < ApplicationController
  def index
    @councils = Current.user.councils.order(created_at: :desc).limit(5)
    @conversations = Current.user.conversations.order(last_message_at: :desc).limit(5)
  end
end
