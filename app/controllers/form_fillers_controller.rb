# frozen_string_literal: true

class FormFillersController < ApplicationController
  PROFILES = [
    {
      id: :advisor_profile,
      prompt: "tasks/advisor_profile",
      schema: :advisor_profile
    },
    {
      id: :council_profile,
      prompt: "tasks/council_profile",
      schema: :council_profile
    }
  ].index_by { _1[:id] }.with_indifferent_access.freeze

  def new
    @profile = PROFILES[params[:profile]]
    return head(:unprocessable_entity) unless @profile.present?

    @filler_id = SecureRandom.uuid
    render :new, layout: false
  end

  def create
    @filler_id = params[:filler_id].to_s
    @profile = PROFILES[params[:profile]]
    return head(:unprocessable_entity) unless @profile.present? && @filler_id.present?

    description = params[:description].to_s.strip
    if description.blank?
      @error = I18n.t("form_fillers.errors.description_blank")
      return render partial: "form_fillers/form", status: :unprocessable_entity
    end

    AI.generate_text(
      prompt: @profile[:prompt],
      schema: @profile[:schema],
      description: description,
      space: Current.space,
      handler: { type: :turbo_form_filler, filler_id: @filler_id },
      async: true
    )

    render partial: "form_fillers/pending"
  rescue AI::ResolutionError, AI::Client::Error => e
    @error = e.message
    render partial: "form_fillers/error", status: :unprocessable_entity
  end
end
