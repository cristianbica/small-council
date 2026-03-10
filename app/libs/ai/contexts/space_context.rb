# frozen_string_literal: true

module AI
  module Contexts
    class SpaceContext < BaseContext
      attr_reader :space, :account

      def initialize(space: nil, account: nil, **args)
        super(**args)
        @space = space
        @account = account
      end

      def model
        account.default_llm_model&.enabled? ? account.default_llm_model : account.llm_models.enabled.free.first
      end
    end
  end
end
