module ApplicationHelper
  # Return appropriate badge class for conversation status
  def status_badge_class(conversation)
    case conversation.status
    when "active"
      "badge-success"
    when "concluding"
      "badge-warning"
    when "resolved"
      "badge-primary"
    when "archived"
      "badge-ghost"
    else
      "badge-ghost"
    end
  end

  # Check if user can delete the conversation
  def can_delete_conversation?(conversation)
    conversation.deletable_by?(Current.user)
  end
end
