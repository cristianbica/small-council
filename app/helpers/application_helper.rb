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

  # Check if user can finish the conversation
  # Available for: On Demand, Silent, Round Robin, and Moderated modes
  def can_finish_conversation?(conversation)
    # Only conversation starter or council creator can finish
    return false unless conversation.user_id == Current.user.id || conversation.council.user_id == Current.user.id

    # Show finish button for manual conclusion in these modes
    conversation.on_demand? || conversation.silent? || conversation.round_robin? || conversation.moderated?
  end

  # Check if user can delete the conversation
  def can_delete_conversation?(conversation)
    conversation.user_id == Current.user.id || conversation.council.user_id == Current.user.id
  end
end
