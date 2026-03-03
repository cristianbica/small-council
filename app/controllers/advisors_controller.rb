class AdvisorsController < ApplicationController
  before_action :set_space
  before_action :set_advisor, only: [ :show, :edit, :update, :destroy ]

  def index
    @advisors = @space.non_scribe_advisors.order(:name)
    @scribe = @space.advisors.find_by("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")
  end

  def show
  end

  def new
    @advisor = @space.advisors.new
  end

  def create
    @advisor = @space.advisors.new(advisor_params)
    @advisor.account = Current.account

    if @advisor.save
      redirect_to space_advisors_path(@space), notice: "Advisor '#{@advisor.name}' was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @advisor.update(advisor_params)
      redirect_to space_advisors_path(@space), notice: "Advisor '#{@advisor.name}' was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @advisor.destroy
      redirect_to space_advisors_path(@space), notice: "Advisor was successfully deleted."
    else
      redirect_to space_advisors_path(@space), alert: "Cannot delete advisor that has messages."
    end
  end

  def generate_prompt
    concept = params[:concept]

    if concept.blank?
      render json: { error: "Concept is required" }, status: :unprocessable_entity
      return
    end

    begin
      generator = AI::ContentGenerator.new
      result = generator.generate_advisor_profile(
        description: concept,
        account: Current.account
      )
      render json: result
    rescue AI::ContentGenerator::NoModelError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue AI::ContentGenerator::GenerationError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def set_space
    if params[:space_id]
      @space = Current.account.spaces.find(params[:space_id])
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to spaces_path, alert: "Space not found."
  end

  def set_advisor
    @advisor = @space.advisors.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to space_advisors_path(@space), alert: "Advisor not found."
  end

  def advisor_params
    params.require(:advisor).permit(:name, :short_description, :system_prompt, :llm_model_id)
  end
end
