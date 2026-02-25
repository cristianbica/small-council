class AdvisorsController < ApplicationController
  before_action :set_council
  before_action :set_advisor, only: [ :edit, :update, :destroy ]
  before_action :require_creator

  def new
    @advisor = @council.advisors.new
  end

  def create
    @advisor = Current.account.advisors.new(advisor_params)

    if @advisor.save
      @council.council_advisors.create!(advisor: @advisor, position: @council.council_advisors.count)
      redirect_to @council, notice: "Advisor added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @advisor.update(advisor_params)
      redirect_to @council, notice: "Advisor updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @advisor.destroy
    redirect_to @council, notice: "Advisor removed successfully."
  end

  def generate_prompt
    description = params[:description]

    if description.blank?
      render json: { error: "Description is required" }, status: :unprocessable_entity
      return
    end

    begin
      generated_prompt = PromptGenerator.generate(description: description, account: Current.account)
      render json: { prompt: generated_prompt }
    rescue PromptGenerator::NoModelError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue PromptGenerator::GenerationError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def set_council
    @council = Current.account.councils.find(params[:council_id])
  end

  def set_advisor
    @advisor = @council.advisors.find(params[:id])
  end

  def require_creator
    unless @council.user_id == Current.user.id
      redirect_to @council, alert: "Only the creator can manage advisors."
    end
  end

  def advisor_params
    params.require(:advisor).permit(:name, :system_prompt, :llm_model_id).tap do |whitelisted|
      if whitelisted[:llm_model_id].present?
        whitelisted[:llm_model_id] = Current.account.llm_models.find_by(id: whitelisted[:llm_model_id])&.id
      end
    end
  end
end
