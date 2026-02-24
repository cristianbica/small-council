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
      session[:provider_wizard] = @wizard_data.to_h
      redirect_to wizard_providers_path
    when 2
      # Step 2: Authentication - DO NOT store API keys in session
      # Pass API key as query param to step 3 (only in URL for one redirect)
      @wizard_data[:step] = 3
      session[:provider_wizard] = @wizard_data.to_h
      redirect_to wizard_providers_path(api_key: params[:api_key], organization_id: params[:organization_id])
    when 3
      # Step 3: Test connection (handled by test_connection action)
      @wizard_data[:step] = 4
      session[:provider_wizard] = @wizard_data.to_h
      redirect_to wizard_providers_path(api_key: params[:api_key], organization_id: params[:organization_id])
    when 4
      # Step 4: Configure and save
      @wizard_data[:name] = params[:name].presence || default_name(@wizard_data[:provider_type])
      # Rails checkbox sends "0" when unchecked, "1" when checked
      @wizard_data[:enabled] = params[:enabled] == "1"

      # Create the provider - API key comes directly from params (hidden field), not session
      @provider = Current.account.providers.new(
        name: @wizard_data[:name],
        provider_type: @wizard_data[:provider_type],
        api_key: params[:api_key],
        organization_id: params[:organization_id],
        enabled: @wizard_data[:enabled]
      )

      if @provider.save
        session.delete(:provider_wizard)
        redirect_to providers_path, notice: "Provider '#{@provider.name}' was successfully added."
        nil
      else
        render :wizard, status: :unprocessable_entity
        nil
      end
    end
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

  # GET /providers/models?provider_id=123
  # If provider_id provided, show only that provider's models
  # If not provided, show all models from all providers
  def models
    if params[:id]
      # Member route - /providers/:id/models
      @provider = Current.account.providers.find(params[:id])
      @models = LLM::ModelManager.available_models(Current.account)
                                 .select { |m| m.provider == @provider }
    elsif params[:provider_id]
      # Collection route with provider_id - /providers/models?provider_id=123
      @provider = Current.account.providers.find(params[:provider_id])
      @models = LLM::ModelManager.available_models(Current.account)
                                 .select { |m| m.provider == @provider }
    else
      @provider = nil
      @models = LLM::ModelManager.available_models(Current.account)
    end
  end

  # POST /providers/toggle_model
  # Params: provider_id, model_id, enabled (true/false)
  def toggle_model
    provider = Current.account.providers.find(params[:provider_id])
    model_id = params[:model_id]
    enabled = params[:enabled] == "true"

    if enabled
      llm_model = LLM::ModelManager.enable_model(Current.account, provider, model_id)
      message = "Model '#{llm_model.name}' enabled successfully"
    else
      llm_model = LLM::ModelManager.disable_model(Current.account, provider, model_id)
      message = "Model '#{llm_model&.name || model_id}' disabled successfully"
    end

    respond_to do |format|
      format.turbo_stream do
        # Build model info from the saved record (no API call needed)
        model_info = LLM::ModelManager::ModelInfo.new(
          provider: provider,
          model_id: model_id,
          name: llm_model&.name || model_id.split("/").last,
          enabled: enabled,
          llm_model: llm_model,
          capabilities: llm_model&.capabilities || {}
        )

        render turbo_stream: turbo_stream.replace(
          "model_toggle_#{provider.id}_#{model_id}",
          partial: "providers/model_toggle",
          locals: { provider: provider, model_info: model_info }
        )
      end
      format.html { redirect_back fallback_location: providers_path, notice: message }
      format.json { render json: { success: true, message: message } }
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    logger.error "[toggle_model] Error: #{e.class} - #{e.message}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "model_toggle_#{params[:provider_id]}_#{params[:model_id]}",
          html: "<span class='text-error' title='#{e.message}'>Error</span>"
        ), status: :unprocessable_entity
      end
      format.html { redirect_back fallback_location: providers_path, alert: "Error: #{e.message}" }
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
    end
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
    when "openrouter" then "OpenRouter"
    else "AI Provider"
    end
  end
end
