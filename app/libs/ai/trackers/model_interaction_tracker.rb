# frozen_string_literal: true

require "json"

module AI
  module Trackers
    class ModelInteractionTracker
      attr_reader :task, :context

      def initialize(task: nil, context: nil, **)
        @task = task
        @context = context
        @started_at = nil
        @tool_trace = []
      end

      def register(chat)
        return unless recordable?

        chat.before_message do
          start_timing
        end

        chat.after_message do |response|
          record_chat(chat: chat, response: response)
        end

        chat.before_tool_call do |tool_call|
          record_tool_call(tool_call)
        end

        chat.after_tool_call do |tool_call, result|
          record_tool_result(tool_call, result)
        end
      end

      def track(_result)
        persist_tool_trace!
      end

      private

      def start_timing
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def record_chat(chat:, response:)
        return unless recordable?
        return unless response&.role == :assistant

        create_interaction!(
          interaction_type: "chat",
          request_payload: build_chat_request_payload(chat, response),
          response_payload: build_chat_response_payload(response),
          model_identifier: chat.model&.id,
          input_tokens: response.input_tokens || 0,
          output_tokens: response.output_tokens || 0,
          duration_ms: compute_duration_ms
        )

        start_timing
      rescue => e
        Rails.logger.error "[AI::Trackers::ModelInteractionTracker] Failed to record chat: #{e.message}"
      end

      def record_tool_call(tool_call)
        @tool_start_times ||= {}
        @tool_start_times[tool_call.id] = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        @tool_trace << {
          type: "tool_call",
          id: tool_call.id,
          name: tool_call.name,
          arguments: normalize_payload(tool_call.arguments)
        }
        persist_tool_trace!
      end

      def record_tool_result(tool_call, result)
        return unless recordable?

        @tool_start_times ||= {}
        start_time = @tool_start_times.delete(tool_call.id)
        return unless start_time

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        duration_ms = (elapsed * 1000).round(1)

        create_interaction!(
          interaction_type: "tool",
          request_payload: {
            tool_name: tool_call.name,
            tool_call_id: tool_call.id,
            arguments: tool_call.arguments
          },
          response_payload: {
            tool_name: tool_call.name,
            result: result.to_s
          },
          model_identifier: nil,
          input_tokens: 0,
          output_tokens: 0,
          duration_ms: duration_ms
        )

        @tool_trace << {
          type: "tool_result",
          tool_call_id: tool_call.id,
          tool_name: tool_call.name,
          result: normalize_payload(result)
        }
        persist_tool_trace!
      rescue => e
        Rails.logger.error "[AI::Trackers::ModelInteractionTracker] Failed to record tool: #{e.message}"
      end

      def recordable?
        message_id.present? && account_id.present?
      end

      def message_id
        context[:message]&.id
      end

      def account_id
        (context[:account] || context[:space]&.account)&.id
      end

      def create_interaction!(interaction_type:, request_payload:, response_payload:,
                              model_identifier:, input_tokens:, output_tokens:, duration_ms:)
        sequence = ModelInteraction.where(message_id: message_id).count

        ModelInteraction.create!(
          account_id: account_id,
          message_id: message_id,
          sequence: sequence,
          interaction_type: interaction_type,
          request_payload: request_payload,
          response_payload: response_payload,
          model_identifier: model_identifier,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          duration_ms: duration_ms
        )
      end

      def compute_duration_ms
        return nil unless @started_at

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
        (elapsed * 1000).round(1)
      end

      def build_chat_request_payload(chat, response)
        begin
          request_body = response&.raw&.env&.request_body
          return JSON.parse(request_body) if request_body.present?
        rescue JSON::ParserError, TypeError, NoMethodError
        end

        all_messages = chat.respond_to?(:messages) ? chat.messages : []
        response_index = all_messages.rindex(response)
        input_messages = response_index ? all_messages[0...response_index] : all_messages[0..-2]

        system_messages = input_messages.select { |message| message.role == :system }
        non_system_messages = input_messages.reject { |message| message.role == :system }

        payload = {
          model: chat.model&.id,
          provider: chat.model&.provider,
          temperature: chat.instance_variable_get(:@temperature),
          tools: serialize_tools(chat)
        }

        unless system_messages.empty?
          payload[:system_prompt] = system_messages.map do |message|
            { type: "text", content: message.content.to_s }
          end
        end

        unless non_system_messages.empty?
          payload[:messages] = non_system_messages.map { |message| format_message(message) }
        end

        payload.compact
      end

      def serialize_tools(chat)
        return [] unless chat.respond_to?(:tools)

        tools = chat.tools
        return tools.as_json if tools.respond_to?(:as_json)

        Array(tools)
      rescue StandardError
        []
      end

      def build_chat_response_payload(response)
        {
          messages: [ format_message(response) ],
          input_tokens: response.input_tokens,
          output_tokens: response.output_tokens,
          model: response.model_id
        }.compact
      end

      def format_message(message)
        formatted = { role: message.role.to_s, parts: [] }
        formatted[:parts] << { type: "text", content: message.content.to_s } if message.content

        if message.tool_calls&.any?
          message.tool_calls.each_value do |tool_call|
            formatted[:parts] << {
              type: "tool_call",
              id: tool_call.id,
              name: tool_call.name,
              arguments: tool_call.arguments
            }
          end
        end

        if message.respond_to?(:tool_call_id) && message.tool_call_id
          formatted[:tool_call_id] = message.tool_call_id
        end

        formatted
      end

      def normalize_payload(value)
        return value.as_json if value.respond_to?(:as_json)

        value
      rescue StandardError
        value.to_s
      end

      def persist_tool_trace!
        message = context[:message]
        return unless message.respond_to?(:update_column)

        message.update_column(:tool_calls, @tool_trace)
      rescue => e
        Rails.logger.error "[AI::Trackers::ModelInteractionTracker] Failed to persist tool trace: #{e.message}"
      end
    end
  end
end
