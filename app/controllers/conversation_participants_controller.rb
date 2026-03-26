class ConversationParticipantsController < ApplicationController
  before_action :set_conversation
  before_action :set_participant
  before_action :authorize_conversation_management

  def edit
    load_form_data
    render_modal
  end

  def update
    load_form_data

    if @participant.update(participant_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "conversation-participants",
              partial: "conversations/participant_badges",
              locals: { conversation: @conversation }
            ),
            turbo_stream.replace("page-modal", view_context.turbo_frame_tag("page-modal", class: "modal"))
          ]
        end

        format.html { redirect_to @conversation, notice: "#{@participant.advisor.name} configuration updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_modal(status: :unprocessable_entity) }
        format.html { render_modal(status: :unprocessable_entity) }
      end
    end
  end

  private

  def set_conversation
    @conversation = Current.space.conversations.find(params[:conversation_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def set_participant
    @participant = @conversation.conversation_participants.includes(:advisor, :llm_model).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def authorize_conversation_management
    return if @conversation.deletable_by?(Current.user)

    redirect_to @conversation, alert: "You are not authorized to update advisor configuration for this conversation."
  end

  def load_form_data
    @available_models = Current.account.llm_models.enabled.order(:name)
  end

  def participant_params
    params.require(:conversation_participant).permit(:llm_model_id, tools: [ :ref, :policy ]).tap do |attrs|
      attrs[:tools] = attrs[:tools].values if attrs[:tools].present?
      attrs[:llm_model_id] = Current.account.llm_models.find_by(id: attrs[:llm_model_id])&.id if attrs[:llm_model_id].present?
    end
  end

  def render_modal(status: :ok)
    render partial: "conversations/participant_config_modal_frame",
           formats: [ :html ],
           locals: {
             conversation: @conversation,
             participant: @participant,
             available_models: @available_models
           },
           status: status
  end
end
