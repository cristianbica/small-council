class CouncilsController < ApplicationController
  before_action :set_space_from_params_or_current, only: [ :index, :new, :create ]
  before_action :set_council, only: [ :show, :edit, :update, :destroy, :edit_advisors, :update_advisors ]
  before_action :require_creator, only: [ :edit, :update, :destroy, :edit_advisors, :update_advisors ]

  def index
    # If nested under space, use that space; otherwise use current space
    @space = @space || Current.space
    @councils = @space.councils.order(created_at: :desc)
  end

  def show
    @advisors = @council.advisors.order(created_at: :asc)
  end

  def new
    @council = Current.space.councils.new
  end

  def create
    @council = Current.space.councils.new(council_params)
    @council.user = Current.user
    @council.account = Current.account

    if @council.save
      redirect_to @council, notice: "Council created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @council.update(council_params)
      redirect_to @council, notice: "Council updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @council.destroy
    redirect_to space_councils_path(Current.space), notice: "Council deleted successfully."
  end

  def edit_advisors
    @council.ensure_scribe_assigned
    @available_advisors = @council.space.advisors.order(:name)
    @scribe_advisor_id = @council.scribe_advisor&.id
    @selected_advisor_ids = @council.advisor_ids
  end

  def update_advisors
    selected_ids = Array(params[:advisor_ids]).map(&:to_i).uniq
    scribe_id = @council.scribe_advisor&.id
    selected_ids << scribe_id if scribe_id.present?

    permitted_ids = @council.space.advisors.where(id: selected_ids).pluck(:id)

    existing_ids = @council.council_advisors.pluck(:advisor_id)
    to_add = permitted_ids - existing_ids
    to_remove = existing_ids - permitted_ids

    ActiveRecord::Base.transaction do
      @council.council_advisors.where(advisor_id: to_remove).destroy_all if to_remove.any?
      to_add.each { |advisor_id| @council.council_advisors.create!(advisor_id: advisor_id) }
    end

    redirect_to @council, notice: "Council advisors updated successfully."
  rescue ActiveRecord::RecordInvalid
    redirect_to edit_advisors_council_path(@council), alert: "Could not update council advisors."
  end

  def generate_description
    concept = params[:concept]

    if concept.blank?
      render json: { error: "Please describe the council's purpose" }, status: :unprocessable_entity
      return
    end

    # Check authorization for existing councils
    if params[:id].present?
      council = Current.space.councils.find(params[:id])
      unless council.user_id == Current.user.id
        render json: { error: "Only the creator can modify this council." }, status: :forbidden
        return
      end
    end

    begin
      generator = AI::ContentGenerator.new
      result = generator.generate_council_description(
        name: concept,
        purpose: concept,
        account: Current.account
      )
      render json: { name: result[:name], description: result[:description] }
    rescue AI::ContentGenerator::NoModelError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue AI::ContentGenerator::GenerationError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def set_space_from_params_or_current
    if params[:space_id]
      @space = Current.account.spaces.find(params[:space_id])
      session[:space_id] = @space.id
      Current.space = @space
    end
  end

  def set_council
    @council = Current.space.councils.find(params[:id])
  end

  def require_creator
    unless @council.user_id == Current.user.id
      redirect_to space_councils_path(Current.space), alert: "Only the creator can modify this council."
    end
  end

  def council_params
    params.require(:council).permit(:name, :description)
  end
end
