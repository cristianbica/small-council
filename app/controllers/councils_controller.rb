class CouncilsController < ApplicationController
  before_action :set_council, only: [ :show, :edit, :update, :destroy ]
  before_action :require_creator, only: [ :edit, :update, :destroy ]

  def index
    @councils = Current.account.councils.order(created_at: :desc)
  end

  def show
    @advisors = @council.advisors.where.not(council_id: nil).order(created_at: :asc)
  end

  def new
    @council = Current.account.councils.new
  end

  def create
    @council = Current.account.councils.new(council_params)
    @council.user = Current.user

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
    redirect_to councils_url, notice: "Council deleted successfully."
  end

  private

  def set_council
    @council = Current.account.councils.find(params[:id])
  end

  def require_creator
    unless @council.user_id == Current.user.id
      redirect_to councils_url, alert: "Only the creator can modify this council."
    end
  end

  def council_params
    params.require(:council).permit(:name, :description)
  end
end
