class ConversationsController < ApplicationController
  before_action :set_council, only: [ :index, :new, :create ]
  before_action :set_conversation, only: [ :show, :update, :finish, :approve_summary, :reject_summary, :regenerate_summary ]

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
    @conversation = @council.conversations.new(conversation_params_for_create)
    @conversation.account = Current.account
    @conversation.user = Current.user

    if @conversation.save
      # Create the first message with the initial_message content
      initial_content = conversation_params[:initial_message].presence || @conversation.title
      @conversation.messages.create!(
        account: Current.account,
        sender: Current.user,
        role: "user",
        content: initial_content
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
    # Build structured memory from form params
    memory = {
      "key_decisions" => params[:key_decisions],
      "action_items" => params[:action_items],
      "insights" => params[:insights],
      "open_questions" => params[:open_questions],
      "raw_summary" => params[:raw_summary],
      "approved_at" => Time.current.iso8601,
      "conversation_id" => @conversation.id
    }

    Rails.logger.info "[ConversationsController#approve_summary] Saving memory for conversation #{@conversation.id}"

    @conversation.update!(
      memory: memory.to_json,
      status: :resolved
    )

    Rails.logger.info "[ConversationsController#approve_summary] Conversation memory saved for space #{@conversation.council.space_id}"

    # Create a proper conversation_summary memory record in the new system
    Memory.create_conversation_summary!(
      conversation: @conversation,
      title: "Summary: #{@conversation.title}",
      content: format_memory_content(memory),
      creator: Current.user
    )

    Rails.logger.info "[ConversationsController#approve_summary] Created conversation_summary memory for conversation #{@conversation.id}"

    redirect_to @conversation, notice: "Conversation resolved and memory saved to space."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[ConversationsController#approve_summary] Failed to save: #{e.message}"
    redirect_to @conversation, alert: "Failed to save memory: #{e.message}"
  rescue => e
    Rails.logger.error "[ConversationsController#approve_summary] Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    redirect_to @conversation, alert: "An error occurred while saving memory."
  end

  def reject_summary
    # Back to active for more discussion
    @conversation.update!(status: :active)
    @conversation.clear_responded_advisors

    redirect_to @conversation, notice: "Conversation continued. You can finish again later."
  end

  def regenerate_summary
    # Only allow if still in concluding state
    if @conversation.concluding?
      @conversation.update!(draft_memory: nil)
      GenerateConversationSummaryJob.perform_later(@conversation.id)
      redirect_to @conversation, notice: "Regenerating summary..."
    else
      redirect_to @conversation, alert: "Can only regenerate while reviewing."
    end
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
    params.require(:conversation).permit(:title, :rules_of_engagement, :initial_message)
  end

  def conversation_params_for_create
    params.require(:conversation).permit(:title, :rules_of_engagement)
  end

  def format_memory_content(memory)
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
    <<~CONTENT
      ## Conversation Summary - #{timestamp}

      **Key Decisions:**
      #{memory["key_decisions"]}

      **Action Items:**
      #{memory["action_items"]}

      **Insights:**
      #{memory["insights"]}

      **Open Questions:**
      #{memory["open_questions"]}

      ---
      *Raw Summary:*
      #{memory["raw_summary"]}
    CONTENT
  end
end
