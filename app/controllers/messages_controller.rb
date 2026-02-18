class MessagesController < ApplicationController
  before_action :set_conversation
  before_action :verify_conversation_in_current_space

  def create
    @message = @conversation.messages.new(message_params)
    @message.account = Current.account
    @message.sender = Current.user
    @message.role = "user"
    @message.status = "complete"

    if @message.save
      # Trigger ScribeCoordinator to determine advisor responses
      coordinator = ScribeCoordinator.new(@conversation)
      responders = coordinator.determine_responders(last_message: @message)

      # Create pending messages and enqueue jobs for each responder
      responders.each do |advisor|
        placeholder = @conversation.messages.create!(
          account: Current.account,
          sender: advisor,
          role: "system",
          content: "[#{advisor.name}] is thinking...",
          status: "pending"
        )

        # Enqueue background job to generate actual response
        GenerateAdvisorResponseJob.perform_later(
          advisor_id: advisor.id,
          conversation_id: @conversation.id,
          message_id: placeholder.id
        )

        # Track for round robin
        @conversation.mark_advisor_spoken(advisor.id)
      end

      redirect_to @conversation, notice: "Message posted successfully."
    else
      @messages = @conversation.messages.chronological.includes(:sender)
      @new_message = @message
      render "conversations/show", status: :unprocessable_entity
    end
  end

  private

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
