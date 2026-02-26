module MemoriesHelper
  # Returns the appropriate CSS class for a memory type badge
  def memory_type_badge_class(memory_type)
    case memory_type
    when "summary"
      "badge-primary"      # Most important - auto-fed to AI
    when "conversation_summary"
      "badge-secondary"    # Linked to conversations
    when "conversation_notes"
      "badge-accent"       # Detailed notes
    when "knowledge"
      "badge-info"         # Standalone knowledge
    else
      "badge-ghost"
    end
  end
end
