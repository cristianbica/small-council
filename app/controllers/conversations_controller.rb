class ConversationsController < ApplicationController
  before_action :set_council, only: [ :index, :new, :create ]
  before_action :set_conversation, only: [ :show, :update, :finish, :approve_summary, :reject_summary ]

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

  def finish
    # Only user who started or council creator can finish
    if @conversation.user_id == Current.user.id || @conversation.council.user_id == Current.user.id
      lifecycle = ConversationLifecycle.new(@conversation)
      lifecycle.begin_conclusion_process
      redirect_to @conversation, notice: "Generating conversation summary..."
    else
      redirect_to @conversation, alert: "Only the conversation starter or council creator can finish."
    end
  end

  def approve_summary
    memory_content = params[:memory] || @conversation.context["draft_memory"]

    # Save approved memory
    @conversation.update!(
      context: @conversation.context.merge("memory" => memory_content),
      status: :resolved
    )

    # Persist to space memory (placeholder - future implementation)
    # append_to_space_memory(@conversation)

    redirect_to @conversation, notice: "Conversation resolved and memory saved."
  end

  def reject_summary
    # Back to active for more discussion
    @conversation.update!(status: :active)
    @conversation.clear_responded_advisors

    redirect_to @conversation, notice: "Conversation continued. You can finish again later."
  end

  private

  def set_council
    # Ensure council belongs to current space
    @council = Current.space.councils.find(params[:council_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to space_councils_path(Current.space), alert: "Council not found."
  end

  def set_conversation
    @conversation = Current.account.conversations.find(params[:id])
    # Verify conversation belongs to a council in current space
    unless @conversation.council.space_id == Current.space.id
      redirect_to space_councils_path(Current.space), alert: "Conversation not found."
    end
  end

  def conversation_params
    params.require(:conversation).permit(:title, :rules_of_engagement)
  end
end
