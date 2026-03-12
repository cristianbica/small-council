# frozen_string_literal: true

module AI
  module Trackers
    class UsageTracker
      attr_reader :task, :context

      def initialize(task: nil, context: nil, **)
        @task = task
        @context = context
      end

      def register(chat)
        # No callback registration - uses track(result) instead
      end

      def track(result)
        track_response(result.response)
      end

      private

      def track_response(response)
        return unless response&.input_tokens && response&.output_tokens

        account = context[:account] || context[:space]&.account
        return unless account

        usage = AI::Model::TokenUsage.new(
          input: response.input_tokens,
          output: response.output_tokens
        )
        cost_cents = ((usage.estimated_cost(context.model) || 0) * 100).round

        UsageRecord.create!(
          account: account,
          provider: context.model.provider.provider_type,
          model: context.model.identifier,
          input_tokens: response.input_tokens,
          output_tokens: response.output_tokens,
          cost_cents: cost_cents,
          message: context[:message],
          recorded_at: Time.current
        )
      rescue => e
        Rails.logger.error "[AI::Trackers::UsageTracker] Failed to track usage: #{e.message}"
      end
    end
  end
end
