class SettingsController < ApplicationController
  def edit
    @account = Current.account
  end

  def update
    @account = Current.account

    if @account.update(account_params)
      redirect_to edit_settings_path, notice: "Settings updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:default_llm_model_id)
  end
end
