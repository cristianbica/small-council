class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_accessible
  before_action :set_message, only: [ :interactions, :retry ]

  def create
    Rails.logger.info "[MessagesController#create] User #{Current.user.id} posting message to conversation #{@conversation.id}"

    command_result = execute_slash_command
    return respond_to_command(command_result) if command_result.present?

    @message = build_user_message

    if @message.save
      Rails.logger.info "[MessagesController#create] Message #{@message.id} saved successfully"

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
    unless @message.error? && @message.sender.is_a?(Advisor)
      redirect_to @conversation, alert: "This message cannot be retried."
      return
    end
    @message.retry!
    head :no_content
  end

  private

  def execute_slash_command
    AI::Commands::CommandRouter.execute(
      content: message_params[:content],
      conversation: @conversation,
      user: Current.user
    )
  end

  def respond_to_command(result)
    return respond_to_command_error(result) unless result[:success]

    if result[:action] == "advisors"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "page-modal",
            partial: "conversations/advisors_modal_frame",
            locals: {
              conversation: @conversation,
              advisors: result[:advisors]
            }
          )
        end

        format.html { redirect_with_command_result(result) }
      end
      return
    end

    if result[:action] == "memories"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "page-modal",
            partial: "conversations/memories_modal_frame",
            locals: {
              conversation: @conversation,
              memories: result[:memories]
            }
          )
        end

        format.html { redirect_with_command_result(result) }
      end
      return
    end

    if result[:action] == "memory"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "page-modal",
            partial: "conversations/memory_modal_frame",
            locals: {
              memory: result[:memory]
            }
          )
        end

        format.html { redirect_with_command_result(result) }
      end
      return
    end

    respond_to do |format|
      format.turbo_stream do
        @conversation.reload
        render turbo_stream: [
          turbo_stream.replace(
            "conversation-participants",
            partial: "conversations/participant_badges",
            locals: { conversation: @conversation }
          ),
          turbo_stream.replace(
            view_context.dom_id(@conversation, :composer),
            partial: "conversations/composer",
            locals: { conversation: @conversation, new_message: Message.new }
          )
        ]
      end

      format.html { redirect_with_command_result(result) }
    end
  end

  def respond_to_command_error(result)
    errored_message = Message.new(content: message_params[:content])

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          view_context.dom_id(@conversation, :composer),
          partial: "conversations/composer",
          locals: {
            conversation: @conversation,
            new_message: errored_message,
            command_error: result[:message]
          }
        ), status: :unprocessable_entity
      end

      format.html do
        if turbo_frame_request?
          render partial: "conversations/composer",
                 locals: {
                   conversation: @conversation,
                   new_message: errored_message,
                   command_error: result[:message]
                 },
                 status: :unprocessable_entity
        else
          redirect_to @conversation, alert: result[:message]
        end
      end
    end
  end

  def redirect_with_command_result(result)
    if result[:success]
      redirect_to @conversation, notice: result[:message]
    else
      redirect_to @conversation, alert: result[:message]
    end
  end

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
end
