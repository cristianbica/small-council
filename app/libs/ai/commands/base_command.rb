# frozen_string_literal: true

module AI
  module Commands
    class BaseCommand
      attr_reader :args, :errors

      def initialize(args)
        @args = args
        @errors = []
      end

      def valid?
        validate
        errors.empty?
      end

      def execute(conversation:, user:)
        raise NotImplementedError
      end

      protected

      def validate
        raise NotImplementedError
      end

      def normalized_advisor_name(raw)
        return nil if raw.blank?

        candidate = raw.to_s.strip.delete_prefix("@").downcase
        return nil unless candidate.match?(Advisor::NAME_FORMAT)

        candidate
      end

      def actor_name(user)
        return user.name if user.respond_to?(:name) && user.name.present?
        return user.display_name if user.respond_to?(:display_name)

        user.to_s
      end

      def create_info_message!(conversation:, user:, content:)
        conversation.messages.create!(
          account: conversation.account,
          sender: user,
          role: "system",
          message_type: "info",
          status: "complete",
          content: content
        )
      end
    end
  end
end
