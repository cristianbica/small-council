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

  # Check if user can finish the conversation (for On Demand and Silent RoE)
  def can_finish_conversation?(conversation)
    # Only conversation starter or council creator can finish
    return false unless conversation.user_id == Current.user.id || conversation.council.user_id == Current.user.id

    # Show for On Demand and Silent RoE modes
    # Or if auto-conclusion hasn't triggered yet
    conversation.on_demand? || conversation.silent?
  end
end
