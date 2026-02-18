class ProvidersController < ApplicationController
  def index
    @providers = Current.account.providers.includes(:llm_models)
  end

  def new
    @provider = Current.account.providers.new
  end

  def create
    @provider = Current.account.providers.new(provider_params)

    if @provider.save
      redirect_to providers_path, notice: "Provider added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @provider = Current.account.providers.find(params[:id])
  end

  def update
    @provider = Current.account.providers.find(params[:id])

    if @provider.update(provider_params)
      redirect_to providers_path, notice: "Provider updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @provider = Current.account.providers.find(params[:id])
    @provider.destroy
    redirect_to providers_path, notice: "Provider removed successfully."
  end

  private

  def provider_params
    params.require(:provider).permit(:name, :provider_type, :api_key, :organization_id, :enabled)
  end
end
