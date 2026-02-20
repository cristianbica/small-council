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

    # provider_type is immutable - remove it from update params
    if @provider.update(provider_params_without_type)
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

  # GET /providers/wizard
  def wizard
    @wizard_data = session[:provider_wizard]&.with_indifferent_access || {}
    @step = @wizard_data[:step] || 1

    # Initialize wizard data if starting fresh
    if @step == 1 && @wizard_data.empty?
      session[:provider_wizard] = { step: 1 }
      @wizard_data = session[:provider_wizard].with_indifferent_access
    end
  end

  # POST /providers/wizard/step
  def wizard_step
    @wizard_data = session[:provider_wizard]&.with_indifferent_access || {}
    current_step = @wizard_data[:step] || 1

    case current_step
    when 1
      # Step 1: Select provider type
      @wizard_data[:provider_type] = params[:provider_type]
      @wizard_data[:step] = 2
    when 2
      # Step 2: Authentication
      @wizard_data[:api_key] = params[:api_key]
      @wizard_data[:organization_id] = params[:organization_id]
      @wizard_data[:step] = 3
    when 3
      # Step 3: Test connection (handled by test_connection action)
      @wizard_data[:step] = 4
    when 4
      # Step 4: Configure and save
      @wizard_data[:name] = params[:name].presence || default_name(@wizard_data[:provider_type])
      # Rails checkbox sends "0" when unchecked, "1" when checked
      @wizard_data[:enabled] = params[:enabled] == "1"

      # Create the provider
      @provider = Current.account.providers.new(
        name: @wizard_data[:name],
        provider_type: @wizard_data[:provider_type],
        api_key: @wizard_data[:api_key],
        organization_id: @wizard_data[:organization_id],
        enabled: @wizard_data[:enabled]
      )

      if @provider.save
        session.delete(:provider_wizard)
        redirect_to providers_path, notice: "Provider '#{@provider.name}' was successfully added."
        return
      else
        render :wizard, status: :unprocessable_entity
        return
      end
    end

    session[:provider_wizard] = @wizard_data.to_h
    redirect_to wizard_providers_path
  end

  # POST /providers/test_connection
  def test_connection
    result = ProviderConnectionTester.test(
      params[:provider_type],
      params[:api_key],
      params[:organization_id]
    )

    if result[:success]
      # Store in session for step 4
      wizard_data = session[:provider_wizard]&.with_indifferent_access || {}
      wizard_data[:tested] = true
      wizard_data[:available_models] = result[:models]
      session[:provider_wizard] = wizard_data.to_h
    end

    render json: result
  end

  # POST /providers/wizard/back
  def wizard_back
    @wizard_data = session[:provider_wizard]&.with_indifferent_access || {}
    current_step = @wizard_data[:step] || 1

    if current_step > 1
      @wizard_data[:step] = current_step - 1
      session[:provider_wizard] = @wizard_data.to_h
    end

    redirect_to wizard_providers_path
  end

  # POST /providers/wizard/cancel
  def wizard_cancel
    session.delete(:provider_wizard)
    redirect_to providers_path
  end

  private

  def provider_params
    params.require(:provider).permit(:name, :provider_type, :api_key, :organization_id, :enabled)
  end

  def provider_params_without_type
    params.require(:provider).permit(:name, :api_key, :organization_id, :enabled)
  end

  def default_name(provider_type)
    case provider_type
    when "openai" then "OpenAI"
    when "anthropic" then "Anthropic"
    when "github" then "GitHub Models"
    else "AI Provider"
    end
  end
end
