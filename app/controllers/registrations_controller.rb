class RegistrationsController < ApplicationController
  skip_before_action :authenticate

  def new
    @account = Account.new
    @account.users.build
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      user = @account.users.first
      user.update!(role: :admin)

      # Create default space for new account
      @account.spaces.create!(
        name: "General",
        description: "Default space for your councils"
      )

      session_record = user.sessions.create!
      cookies.signed.permanent[:session_token] = { value: session_record.id, httponly: true }

      redirect_to root_path, notice: "Welcome to Small Council!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(
      :name, :slug,
      users_attributes: [ :email, :password, :password_confirmation ]
    )
  end
end
