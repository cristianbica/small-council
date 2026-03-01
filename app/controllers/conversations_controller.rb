class ConversationsController < ApplicationController
  before_action :set_council, only: [ :index, :new, :create ], if: -> { params[:council_id].present? }
  before_action :set_conversation, only: [ :show, :update, :destroy, :invite_advisor ]
  before_action :set_sidebar_conversations, only: [ :show ]

  layout :choose_layout

  def index
    if @council
      # Show council-specific conversations list
      @conversations = @council.conversations.recent
      render :index
    else
      # For adhoc conversations, redirect to most recent or auto-create one
      last_conversation = Current.account.conversations.adhoc_conversations.recent.first
      if last_conversation
        redirect_to last_conversation
      else
        # Auto-create a new conversation with just the scribe
        auto_create_conversation
      end
    end
  end

  def quick_create
    # Create adhoc conversation with roe_type: :open
    @conversation = Current.account.conversations.new(
      title: "New conversation #{Time.current.strftime('%b %d, %H:%M')}",
      conversation_type: :adhoc,
      roe_type: :open,
      user: Current.user
    )

    if @conversation.save
      # Add only scribe as participant
      @conversation.ensure_scribe_present!

      redirect_to @conversation, notice: "New conversation started. Add advisors by using /invite @advisor or type your first message."
    else
      redirect_to conversations_path, alert: "Failed to create conversation."
    end
  end

  def show
    @messages = @conversation.messages.chronological.includes(:sender, :model_interactions)
    @new_message = Message.new
    @available_advisors = available_advisors_for_invite
  end

  def new
    if @council
      @conversation = @council.conversations.new
    else
      @conversation = Current.account.conversations.new(conversation_type: :adhoc)
    end
    @available_advisors = available_advisors_for_conversation
  end

  def create
    if params[:council_id].present?
      create_council_meeting
    else
      create_adhoc_conversation
    end
  end

  def update
    # Only allow updating RoE type for now
    if @conversation.update(conversation_params)
      redirect_to @conversation, notice: "Conversation updated to #{@conversation.roe_type.humanize} mode."
    else
      redirect_to @conversation, alert: "Failed to update conversation."
    end
  end

  def invite_advisor
    unless @conversation.active?
      redirect_to @conversation, alert: "Can only invite advisors to active conversations."
      return
    end

    advisor_id = params[:advisor_id]
    advisor = Current.account.advisors.find_by(id: advisor_id)

    if advisor.nil?
      redirect_to @conversation, alert: "Advisor not found."
      return
    end

    if @conversation.advisors.include?(advisor)
      redirect_to @conversation, alert: "#{advisor.name} is already in this conversation."
      return
    end

    if @conversation.add_advisor(advisor)
      # Send welcome message from system
      @conversation.messages.create!(
        account: Current.account,
        sender: Current.user,
        role: "system",
        content: "#{advisor.name} has joined the conversation.",
        status: "complete"
      )
      redirect_to @conversation, notice: "#{advisor.name} has been invited."
    else
      redirect_to @conversation, alert: "Failed to invite advisor."
    end
  end

  def destroy
    unless can_manage_conversation?
      redirect_to @conversation, alert: "Only the conversation starter can delete this conversation."
      return
    end

    @conversation.destroy!

    respond_to do |format|
      redirect_path = if @conversation.council_meeting?
        council_conversations_path(@conversation.council)
      else
        conversations_path
      end

      format.html { redirect_to redirect_path, notice: "Conversation deleted successfully." }
      format.turbo_stream { redirect_to redirect_path, notice: "Conversation deleted successfully." }
    end
  rescue => e
    Rails.logger.error "[ConversationsController#destroy] Error deleting conversation #{@conversation.id}: #{e.message}"
    redirect_to @conversation, alert: "Failed to delete conversation: #{e.message}"
  end

  private

  def set_council
    @council = Current.space.councils.find(params[:council_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to space_councils_path(Current.space), alert: "Council not found."
  end

  def set_conversation
    @conversation = Current.account.conversations.find(params[:id])
    # Verify conversation belongs to current space
    unless conversation_in_current_space?
      redirect_to space_councils_path(Current.space), alert: "Conversation not found."
    end
  end

  def conversation_in_current_space?
    if @conversation.council_meeting?
      @conversation.council.space_id == Current.space.id
    else
      # Adhoc conversations are accessible from any space context
      # Could add additional checks here if needed
      true
    end
  end

  def can_manage_conversation?
    @conversation.user_id == Current.user.id
  end

  def create_council_meeting
    @conversation = @council.conversations.new(conversation_params_for_create)
    @conversation.account = Current.account
    @conversation.user = Current.user
    @conversation.conversation_type = :council_meeting

    if @conversation.save
      # Add council advisors as participants within the same transaction
      ActiveRecord::Base.transaction do
        add_council_participants(@conversation)
        @conversation.reload
      end

      # Create initial message outside transaction
      initial_content = conversation_params[:initial_message].presence || @conversation.title
      @conversation.messages.create!(
        account: Current.account,
        sender: Current.user,
        role: "user",
        content: initial_content
      )

      redirect_to @conversation, notice: "Meeting started successfully."
    else
      @available_advisors = available_advisors_for_conversation
      render :new, status: :unprocessable_entity
    end
  end

  def create_adhoc_conversation
    @conversation = Current.account.conversations.new(conversation_params_for_create)
    @conversation.account = Current.account
    @conversation.user = Current.user
    @conversation.conversation_type = :adhoc
    @conversation.council = nil
    @conversation.roe_type = conversation_params[:roe_type].presence || "open"

    # Validate that at least one advisor is selected
    advisor_ids = conversation_params[:advisor_ids] || []
    if advisor_ids.empty?
      @conversation.errors.add(:advisor_ids, "Please select at least one advisor")
      @available_advisors = available_advisors_for_conversation
      render :new, status: :unprocessable_entity
      return
    end

    if @conversation.save
      # Add selected advisors as participants
      add_selected_participants(@conversation)

      # Ensure scribe is present
      @conversation.ensure_scribe_present!

      # Create initial message
      initial_content = conversation_params[:initial_message].presence || @conversation.title
      @conversation.messages.create!(
        account: Current.account,
        sender: Current.user,
        role: "user",
        content: initial_content
      )

      redirect_to @conversation, notice: "Conversation started successfully."
    else
      @available_advisors = available_advisors_for_conversation
      render :new, status: :unprocessable_entity
    end
  end

  def auto_create_conversation
    # Auto-create adhoc conversation with just the scribe
    @conversation = Current.account.conversations.new(
      title: "New conversation #{Time.current.strftime('%b %d, %H:%M')}",
      user: Current.user,
      conversation_type: :adhoc,
      roe_type: :open
    )

    if @conversation.save
      # Ensure scribe is present (only participant)
      @conversation.ensure_scribe_present!
      @conversation.reload

      redirect_to @conversation, notice: "New conversation created."
    else
      # If auto-creation fails, redirect to new form
      redirect_to new_conversation_path, alert: "Could not auto-create conversation."
    end
  end

  def add_council_participants(conversation)
    @council.advisors.each do |advisor|
      role = advisor.scribe? ? "scribe" : "advisor"
      position = @council.council_advisors.find_by(advisor: advisor)&.position || 0
      conversation.conversation_participants.create!(
        advisor: advisor,
        role: role,
        position: position
      )
    end
  end

  def add_selected_participants(conversation)
    advisor_ids = conversation_params[:advisor_ids] || []
    advisors = Current.account.advisors.where(id: advisor_ids).where(is_scribe: false)

    advisors.each_with_index do |advisor, index|
      conversation.conversation_participants.create!(
        advisor: advisor,
        role: "advisor",
        position: index
      )
    end
  end

  def available_advisors_for_conversation
    Current.space.non_scribe_advisors
  end

  def available_advisors_for_invite
    return [] unless @conversation&.active? && Current.space
    Current.space.non_scribe_advisors.where.not(id: @conversation.advisor_ids)
  end

  def conversation_params
    params.require(:conversation).permit(:title, :roe_type, :initial_message, advisor_ids: [])
  end

  def conversation_params_for_create
    params.require(:conversation).permit(:title, :roe_type)
  end

  def set_sidebar_conversations
    return unless @conversation&.adhoc?
    @sidebar_conversations = Current.account.conversations.adhoc_conversations.recent.limit(10)
  end

  def choose_layout
    if action_name == "show" && @conversation&.adhoc?
      "conversation"
    else
      "application"
    end
  end
end
