class AdvisorsController < ApplicationController
  before_action :set_council
  before_action :set_advisor, only: [ :edit, :update, :destroy ]
  before_action :require_creator

  def new
    @advisor = @council.advisors.new
  end

  def create
    @advisor = @council.advisors.new(advisor_params)
    @advisor.account = Current.account
    @advisor.council = @council

    # Set default model values for simple advisors
    @advisor.model_provider ||= "openai"
    @advisor.model_id ||= "gpt-4"

    if @advisor.save
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
    params.require(:advisor).permit(:name, :system_prompt)
  end
end
