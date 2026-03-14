# frozen_string_literal: true

module MessagesHelper
  # Returns display content for a message, with special handling for compaction messages
  # This is a UI-only display helper - it does not modify the message in the database
  #
  # @param message [Message] the message to display
  # @return [String] the content to display in the UI
  def message_display_content(message)
    return message.content unless message.compaction?

    if message.pending? || message.responding?
      "Compacting ..."
    elsif message.complete?
      "Content compacted"
    else
      message.content
    end
  end
end
