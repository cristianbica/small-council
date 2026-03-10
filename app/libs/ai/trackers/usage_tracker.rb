# frozen_string_literal: true

module AI
  module Trackers
    class UsageTracker
      attr_reader :task, :context

      def initialize(task: nil, context: nil, **)
        @task = task
        @context = context
      end

      def track(result)
        response = result.response
        return unless response&.input_tokens && response&.output_tokens

        account = context_value(:account) || context_value(:space)&.account
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
          message: context_value(:message),
          recorded_at: Time.current
        )
      rescue => e
        Rails.logger.error "[AI::Trackers::UsageTracker] Failed to track usage: #{e.message}"
      end

      private

      def context_value(key)
        return context.public_send(key) if context.respond_to?(key)
        return context[key] if context.respond_to?(:[]) && context.respond_to?(:key?) && context.key?(key)
        return context[key.to_s] if context.respond_to?(:[]) && context.respond_to?(:key?) && context.key?(key.to_s)
        return context[key] if context.respond_to?(:[])
        return context[key.to_s] if context.respond_to?(:[])

        nil
      end
    end
  end
end
