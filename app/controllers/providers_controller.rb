class ProvidersController < ApplicationController
  def index
    @providers = Current.account.providers.includes(:llm_models)
  end

  def new
    provider_type = normalize_provider_type(params[:provider_type])
    @provider = Current.account.providers.new(provider_type: provider_type, enabled: true)
    @selected_provider_type = @provider.provider_type

    if turbo_frame_request?
      render partial: "providers/provider_form_frame",
             locals: { provider: @provider, selected_provider_type: @selected_provider_type }
    end
  end

  def create
    @provider = Current.account.providers.new(provider_params)
    @selected_provider_type = @provider.provider_type

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

  # POST /providers/test_connection
  def test_connection
    result = ProviderConnectionTester.test(
      params[:provider_type],
      params[:api_key],
      params[:organization_id]
    )

    render json: result
  end

  # GET /providers/models?provider_id=123
  # If provider_id provided, show only that provider's models
  # If not provided, show all models from all providers
  def models
    if params[:id]
      # Member route - /providers/:id/models
      @provider = Current.account.providers.find(params[:id])
      @models = AI::ModelManager.available_models(Current.account)
                                 .select { |m| m.provider == @provider }
    elsif params[:provider_id]
      # Collection route with provider_id - /providers/models?provider_id=123
      @provider = Current.account.providers.find(params[:provider_id])
      @models = AI::ModelManager.available_models(Current.account)
                                 .select { |m| m.provider == @provider }
    else
      @provider = nil
      @models = AI::ModelManager.available_models(Current.account)
    end
  end

  # POST /providers/toggle_model
  # Params: provider_id, model_id, enabled (true/false)
  def toggle_model
    provider = Current.account.providers.find(params[:provider_id])
    model_id = params[:model_id]
    enabled = params[:enabled] == "true"

    if enabled
      llm_model = AI::ModelManager.enable_model(Current.account, provider, model_id)
      message = "Model '#{llm_model.name}' enabled successfully"
    else
      llm_model = AI::ModelManager.disable_model(Current.account, provider, model_id)
      message = "Model '#{llm_model&.name || model_id}' disabled successfully"
    end

    respond_to do |format|
      format.turbo_stream do
        # Build model info from the saved record (no API call needed)
        model_info = AI::ModelManager::ModelInfo.new(
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

  def normalize_provider_type(provider_type)
    return nil if provider_type.blank?
    return provider_type if Provider.provider_types.key?(provider_type)

    nil
  end

  def provider_form_partial(provider_type)
    case provider_type
    when "openai"
      "providers/new_form_openai"
    when "openrouter"
      "providers/new_form_openrouter"
    when "anthropic"
      "providers/new_form_anthropic"
    else
      "providers/new_form_placeholder"
    end
  end
end
