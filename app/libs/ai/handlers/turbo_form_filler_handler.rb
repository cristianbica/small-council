# frozen_string_literal: true

require "json"

module AI
  module Handlers
    class TurboFormFillerHandler < BaseHandler
      attr_reader :filler_id

      def initialize(task: nil, context: nil, filler_id:, **)
        super(task:, context:)
        @filler_id = filler_id
      end

      def handle(result)
        return broadcast("error", error: result.error&.message || I18n.t("form_fillers.errors.unable_to_generate")) if result.failure?

        broadcast("success", payload: result.response.content.to_json)
      rescue StandardError => e
        broadcast("error", error: e.message)
      end

      private

      def broadcast(state, payload: nil, error: nil)
        Turbo::StreamsChannel.broadcast_replace_to(
          "form_filler_result_#{filler_id}",
          target: "form_filler_result_#{filler_id}",
          partial: "form_fillers/result",
          locals: {
            filler_id: filler_id,
            state: state,
            payload: payload,
            error: error
          }
        )
      end
    end
  end
end
