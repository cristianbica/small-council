class CouncilsController < ApplicationController
  before_action :set_space_from_params_or_current, only: [ :index, :new, :create ]
  before_action :set_council, only: [ :show, :edit, :update, :destroy ]
  before_action :require_creator, only: [ :edit, :update, :destroy ]

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
      result = ContentGenerator.generate(profile: :council, context: concept, account: Current.account)
      render json: { name: result[:name], description: result[:description] }
    rescue ContentGenerator::NoModelError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ContentGenerator::GenerationError => e
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
