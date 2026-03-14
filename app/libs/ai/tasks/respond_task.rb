# frozen_string_literal: true

module AI
  module Tasks
    class RespondTask < BaseTask
      self.agent = :advisor

      def initialize(context:, prompt: nil, tools: nil)
        super(context: context, tools: tools)
        @prompt = prompt
      end

      def prepare(chat)
        chat.instructions(system_prompt)
        conversation_messages.each do |message|
          chat.add_message(**message.except(:sender_name))
        end
      end

      def run(result, trackers: [])
        mark_message_responding!
        super(result, trackers: trackers)
      end

      private

      def mark_message_responding!
        message = context.message
        return unless message&.pending?

        message.update!(status: "responding")
      end

      def system_prompt
        # Always start with base advisor context (role, space, council, advisor-specific)
        base_prompt = agent.system_prompt

        # Append RoE-specific instructions if provided
        if @prompt
          custom_prompt = AI.prompt(@prompt, context: context)
          "#{base_prompt}\n\n#{custom_prompt}"
        else
          base_prompt
        end
      end

      def conversation_messages
        scope = context.conversation.messages.complete.chronological
        scope = scope.where.not(id: context.message.previous_message.id) if context.message&.previous_message&.compaction?
        scope = scope.since_last_compaction

        scope.filter_map do |message|
          # Skip replies from advisors to the message we're responding to, so this response won't be biased
          next if message.in_reply_to_id.present? && message.in_reply_to_id == context.message&.id

          next if context.advisor.non_scribe? && message.from_non_scribe_advisor? && !message.mentions?(context.advisor)

          build_message(message)
        end
      end

      def build_message(message)
        sender_name = sender_display_name(message.sender)
        {
          role: normalized_role(message.role),
          content: outbound_message_content(message.content, sender_name, message.role),
          sender_name: sender_name
        }
      end

      def normalized_role(role)
        role.to_s == "advisor" ? :assistant : role.to_sym
      end

      def sender_display_name(sender)
        return sender.display_name if sender.respond_to?(:display_name)
        return sender.name if sender.respond_to?(:name)

        sender.to_s
      end

      def outbound_message_content(content, sender_name, role)
        label = sender_name.presence || role.to_s
        "[speaker: #{label}] #{content}"
      end

      def build_tool_trace_messages(message)
        entries = message.respond_to?(:tool_calls) ? Array(message.tool_calls) : []
        return [] if entries.empty?

        messages = []

        entries.each do |entry|
          next unless entry.is_a?(Hash)
          entry = entry.deep_symbolize_keys
          next unless entry[:type] == "tool_result"

          messages << {
            role: :tool,
            content: entry[:result].to_json,
            tool_call_id: entry[:tool_call_id]
          }
        end

        messages
      rescue StandardError
        []
      end
    end
  end
end
