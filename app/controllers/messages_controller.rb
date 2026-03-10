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
      AI.runtime_for_conversation(@conversation).user_posted(@message)

      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to @conversation }
      end
    else
      Rails.logger.warn "[MessagesController#create] Failed to save message: #{@message.errors.full_messages.join(', ')}"

      if turbo_frame_request?
        render partial: "conversations/composer",
               locals: { conversation: @conversation, new_message: @message },
               status: :unprocessable_entity
      else
        redirect_to @conversation, alert: "Failed to create message"
      end
    end
  end

  def interactions
    @interactions = @message.model_interactions.chronological
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
      partial: "conversations/message",
      locals: { message: @message, current_user: nil }
    )

    AI.generate_advisor_response(
      advisor: @message.sender,
      message: @message,
      async: true
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
