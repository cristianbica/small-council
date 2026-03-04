class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_accessible
  before_action :set_message, only: [ :interactions, :retry ]

  def create
    Rails.logger.info "[MessagesController#create] User #{Current.user.id} posting message to conversation #{@conversation.id}"

    @message = build_user_message

    if @message.save
      Rails.logger.info "[MessagesController#create] Message #{@message.id} saved successfully"

      enqueue_adhoc_title_generation(@message)

      lifecycle = ConversationLifecycle.new(@conversation)
      lifecycle.user_posted_message(@message)

      redirect_to @conversation
    else
      Rails.logger.warn "[MessagesController#create] Failed to save message: #{@message.errors.full_messages.join(', ')}"
      @messages = @conversation.messages.where.not(status: "pending").chronological.includes(:sender)
      @new_message = @message
      @available_advisors = available_advisors_for_invite
      render "conversations/show", status: :unprocessable_entity
    end
  end

  def interactions
    @interactions = @message.model_interactions.chronological
    frame_id = "interactions-frame-#{@message.id}"
    render partial: "messages/interactions_frame", locals: {
      frame_id: frame_id,
      message: @message,
      interactions: @interactions
    }
  end

  def retry
    unless retryable_advisor_api_error?(@message)
      redirect_to @conversation, alert: "This message cannot be retried."
      return
    end

    @message.update!(
      status: "responding",
      content: "..."
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{@conversation.id}",
      target: "message_#{@message.id}",
      partial: "messages/message",
      locals: { message: @message, current_user: nil }
    )

    GenerateAdvisorResponseJob.perform_later(
      advisor_id: @message.sender_id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    redirect_to @conversation, notice: "Retry started."
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

  def set_message
    @message = @conversation.messages.find(params[:id])
  end

  def verify_conversation_accessible
    return if @conversation.space_id == Current.space.id

    redirect_to conversations_path, alert: "You can only post to conversations in your current space."
  end

  def message_params
    params.require(:message).permit(:content)
  end

  def enqueue_adhoc_title_generation(message)
    return unless @conversation.adhoc?
    return if @conversation.title_locked?

    user_message_count = @conversation.messages.where(role: "user", sender_type: "User").count
    return unless user_message_count == 1

    GenerateConversationTitleJob.perform_later(@conversation.id, message.id)
  end

  def retryable_advisor_api_error?(message)
    return false unless message.sender.is_a?(Advisor)
    return false unless message.error?

    message.content.to_s.include?("API Error:") || message.content.to_s.match?(/Empty response from AI/)
  end
end
