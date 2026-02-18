class ConversationsController < ApplicationController
  before_action :set_council, only: [ :index, :new, :create ]
  before_action :set_conversation, only: [ :show, :update ]

  def index
    @conversations = @council.conversations.recent
  end

  def show
    @messages = @conversation.messages.chronological.includes(:sender)
    @new_message = Message.new
  end

  def new
    @conversation = @council.conversations.new
  end

  def create
    @conversation = @council.conversations.new(conversation_params)
    @conversation.account = Current.account
    @conversation.user = Current.user

    if @conversation.save
      # Create the first message with the conversation title as content
      @conversation.messages.create!(
        account: Current.account,
        sender: Current.user,
        role: "user",
        content: @conversation.title
      )

      redirect_to @conversation, notice: "Conversation started successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @conversation.update(conversation_params)
      redirect_to @conversation, notice: "Rules of Engagement updated to #{@conversation.rules_of_engagement.humanize}."
    else
      redirect_to @conversation, alert: "Failed to update Rules of Engagement."
    end
  end

  private

  def set_council
    @council = Current.account.councils.find(params[:council_id])
  end

  def set_conversation
    @conversation = Current.account.conversations.find(params[:id])
  end

  def conversation_params
    params.require(:conversation).permit(:title, :rules_of_engagement)
  end
end
