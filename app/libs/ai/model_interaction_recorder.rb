# frozen_string_literal: true

module AI
  class ModelInteractionRecorder
    def initialize(message_id:, account_id:)
      @message_id = message_id
      @account_id = account_id
      @started_at = nil
      @pending_tool_call = nil # Holds on_tool_call data until on_tool_result fires
    end

    # Call before ruby_llm_chat.complete to start timing
    def start_timing
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # on_end_message callback — records LLM completion interactions.
    # chat: the RubyLLM::Chat instance (for @messages, @model, @temperature)
    # response: the RubyLLM::Message passed to on_end_message
    def record_chat(chat:, response:)
      return unless recordable?
      return unless response&.role == :assistant

      duration_ms = compute_duration_ms

      create_interaction!(
        interaction_type: "chat",
        request_payload: build_chat_request_payload(chat, response),
        response_payload: build_chat_response_payload(response),
        model_identifier: chat.model&.id,
        input_tokens: response.input_tokens || 0,
        output_tokens: response.output_tokens || 0,
        duration_ms: duration_ms
      )

      # Reset timer for next round-trip (tool call loops)
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue => e
      Rails.logger.error "[AI::ModelInteractionRecorder] Failed to record chat: #{e.message}"
    end

    # on_tool_call callback — stashes tool call data and starts timing.
    # tool_call: RubyLLM tool call object with .name, .id, .arguments
    def record_tool_call(tool_call)
      @pending_tool_call = {
        name: tool_call.name,
        id: tool_call.id,
        arguments: tool_call.arguments,
        started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }
    end

    # on_tool_result callback — pairs with the pending tool call to record the interaction.
    # result: the tool execution result
    def record_tool_result(result)
      return unless recordable?
      return unless @pending_tool_call

      tool_data = @pending_tool_call
      @pending_tool_call = nil

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_data[:started_at]
      duration_ms = (elapsed * 1000).round(1)

      create_interaction!(
        interaction_type: "tool",
        request_payload: {
          tool_name: tool_data[:name],
          tool_call_id: tool_data[:id],
          arguments: tool_data[:arguments]
        },
        response_payload: {
          tool_name: tool_data[:name],
          result: result.to_s
        },
        model_identifier: nil,
        input_tokens: 0,
        output_tokens: 0,
        duration_ms: duration_ms
      )
    rescue => e
      Rails.logger.error "[AI::ModelInteractionRecorder] Failed to record tool: #{e.message}"
    end

    private

    def recordable?
      @message_id && @account_id
    end

    def create_interaction!(interaction_type:, request_payload:, response_payload:,
                            model_identifier:, input_tokens:, output_tokens:, duration_ms:)
      sequence = ModelInteraction.where(message_id: @message_id).count

      ModelInteraction.create!(
        account_id: @account_id,
        message_id: @message_id,
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
      # Messages up to (but not including) this response
      all_messages = chat.messages
      response_index = all_messages.rindex(response)
      input_messages = response_index ? all_messages[0...response_index] : all_messages[0..-2]

      system_messages = input_messages.select { |m| m.role == :system }
      non_system = input_messages.reject { |m| m.role == :system }

      payload = {
        model: chat.model&.id,
        provider: chat.model&.provider,
        temperature: chat.instance_variable_get(:@temperature)
      }

      unless system_messages.empty?
        payload[:system_prompt] = system_messages.map { |m| { type: "text", content: m.content.to_s } }
      end

      unless non_system.empty?
        payload[:messages] = non_system.map { |m| format_message(m) }
      end

      payload.compact
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
      msg = { role: message.role.to_s, parts: [] }
      msg[:parts] << { type: "text", content: message.content.to_s } if message.content
      if message.tool_calls&.any?
        message.tool_calls.each_value do |tc|
          msg[:parts] << { type: "tool_call", id: tc.id, name: tc.name, arguments: tc.arguments }
        end
      end
      msg[:tool_call_id] = message.tool_call_id if message.respond_to?(:tool_call_id) && message.tool_call_id
      msg
    end
  end
end
