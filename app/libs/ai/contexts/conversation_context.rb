# frozen_string_literal: true

module AI
  module Contexts
    class ConversationContext < BaseContext
      attr_reader :conversation, :advisor, :account, :message

      def initialize(conversation:, advisor: nil, account: nil, message: nil, **args)
        super(**args)
        @conversation = conversation
        @advisor = advisor
        @account = account || conversation&.account || advisor&.account
        @message = message

        raise ArgumentError, "Conversation is required" unless @conversation
      end

      def space
        conversation.space
      end

      def council
        conversation.council
      end

      def user
        conversation.user
      end

      def scribe?
        advisor&.scribe? || false
      end

      def model
        advisor&.effective_llm_model || account&.default_llm_model || account&.llm_models&.enabled&.first
      end
    end
  end
end
