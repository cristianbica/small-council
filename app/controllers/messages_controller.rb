class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_accessible

  def create
    Rails.logger.info "[MessagesController#create] User #{Current.user.id} posting message to conversation #{@conversation.id}"

    @message = build_user_message

    if @message.save
      Rails.logger.info "[MessagesController#create] Message #{@message.id} saved successfully"

      lifecycle = ConversationLifecycle.new(@conversation)
      lifecycle.user_posted_message(@message)

      redirect_to @conversation
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

  def set_conversation
    @conversation = Current.space.conversations.find(params[:conversation_id])
  end

  def verify_conversation_accessible
    return if @conversation.space_id == Current.space.id

    redirect_to conversations_path, alert: "You can only post to conversations in your current space."
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
