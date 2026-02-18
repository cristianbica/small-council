class MessagesController < ApplicationController
  before_action :set_conversation

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

      # Create placeholder messages for each responder
      responders.each do |advisor|
        @conversation.messages.create!(
          account: Current.account,
          sender: advisor,
          role: "system",
          content: "[#{advisor.name}] is thinking...",
          status: "pending"
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

  def message_params
    params.require(:message).permit(:content)
  end
end
