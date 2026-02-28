class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_accessible

  def create
    Rails.logger.info "[MessagesController#create] User #{Current.user.id} posting message to conversation #{@conversation.id}"

    @message = build_user_message

    if @message.save
      Rails.logger.info "[MessagesController#create] Message #{@message.id} saved successfully"

      # Handle command if present
      if @message.command?
        handle_command
      else
        # Normal message flow - delegate to ConversationLifecycle
        lifecycle = ConversationLifecycle.new(@conversation)
        responders = lifecycle.user_posted_message(@message)

        Rails.logger.info "[MessagesController#create] Posted message triggered #{responders&.count || 0} advisor(s) to respond"
      end

      redirect_to @conversation, notice: "Message posted successfully."
    else
      Rails.logger.warn "[MessagesController#create] Failed to save message: #{@message.errors.full_messages.join(', ')}"
      @messages = @conversation.messages.chronological.includes(:sender)
      @new_message = @message
      @available_advisors = available_advisors_for_invite
      render "conversations/show", status: :unprocessable_entity
    end
  end

  private

  def build_user_message
    @conversation.messages.new(message_params).tap do |msg|
      msg.account = Current.account
      msg.sender = Current.user
      msg.role = "user"
      msg.status = "complete"
    end
  end

  def handle_command
    command = CommandParser.parse(@message.content)
    return unless command

    lifecycle = ConversationLifecycle.new(@conversation)

    # Command validation and execution happens in lifecycle
    # We pass nil for the command since lifecycle parses it again
    # This ensures consistent handling
    lifecycle.user_posted_message(@message)
  end

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
  end

  def verify_conversation_accessible
    # For council meetings, verify space context
    if @conversation.council_meeting?
      unless @conversation.council&.space == Current.space
        redirect_to conversations_path, alert: "You can only post to conversations in your current space."
      end
    end
    # Adhoc conversations are accessible from any space context
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
