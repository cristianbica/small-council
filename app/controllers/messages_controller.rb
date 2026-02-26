class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_in_current_space

  def create
    Rails.logger.info "[MessagesController#create] User #{Current.user.id} posting message to conversation #{@conversation.id}"
    Rails.logger.debug "[MessagesController#create] Message content: '#{params.dig(:message, :content)}'"

    @message = build_user_message

    if @message.save
      Rails.logger.info "[MessagesController#create] Message #{@message.id} saved successfully"

      # Delegate to ConversationLifecycle
      Rails.logger.debug "[MessagesController#create] Initializing ConversationLifecycle..."
      lifecycle = ConversationLifecycle.new(@conversation)
      responders = lifecycle.user_posted_message(@message)

      Rails.logger.info "[MessagesController#create] Posted message triggered #{responders&.count || 0} advisor(s) to respond"

      redirect_to @conversation, notice: "Message posted successfully."
    else
      Rails.logger.warn "[MessagesController#create] Failed to save message: #{@message.errors.full_messages.join(', ')}"
      @messages = @conversation.messages.chronological.includes(:sender)
      @new_message = @message
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

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
  end

  def verify_conversation_in_current_space
    unless @conversation.council.space == Current.space
      redirect_to conversations_path, alert: "You can only post to conversations in your current space."
    end
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
