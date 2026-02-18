class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_in_current_space

  def create
    @message = build_user_message

    if @message.save
      # Delegate to ConversationLifecycle
      lifecycle = ConversationLifecycle.new(@conversation)
      lifecycle.user_posted_message(@message)

      redirect_to @conversation, notice: "Message posted successfully."
    else
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
