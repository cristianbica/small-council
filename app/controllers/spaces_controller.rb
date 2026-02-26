class SpacesController < ApplicationController
  before_action :set_space, only: [ :show, :edit, :update ]

  def index
    @spaces = Current.account.spaces.order(created_at: :desc)
  end

  def show
    # Switch to this space and show its councils
    session[:space_id] = @space.id
    Current.space = @space
    redirect_to space_councils_path(@space)
  end

  def new
    @space = Current.account.spaces.new
  end

  def create
    @space = Current.account.spaces.new(space_params)

    if @space.save
      # Switch to the new space
      session[:space_id] = @space.id
      Current.space = @space
      redirect_to space_councils_path(@space), notice: "Space created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @space.update(space_params)
      redirect_to space_councils_path(@space), notice: "Space updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_space
    @space = Current.account.spaces.find(params[:id])
  end

  def space_params
    params.require(:space).permit(:name, :description)
  end
end
