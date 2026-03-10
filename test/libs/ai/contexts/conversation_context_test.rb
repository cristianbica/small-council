# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Contexts
    class ConversationContextTest < ActiveSupport::TestCase
      test "requires conversation" do
        assert_raises(ArgumentError) { ConversationContext.new(conversation: nil) }
      end

      test "delegates space council and user to conversation" do
        conversation = conversations(:one)
        context = ConversationContext.new(conversation: conversation)

        assert_equal conversation.space, context.space
        assert_equal conversation.council, context.council
        assert_equal conversation.user, context.user
      end

      test "scribe? reflects advisor role" do
        normal_advisor = OpenStruct.new(scribe?: false)
        scribe_advisor = OpenStruct.new(scribe?: true)
        conversation = conversations(:one)

        assert_equal false, ConversationContext.new(conversation: conversation, advisor: normal_advisor).scribe?
        assert_equal true, ConversationContext.new(conversation: conversation, advisor: scribe_advisor).scribe?
        assert_equal false, ConversationContext.new(conversation: conversation).scribe?
      end

      test "model picks advisor model first" do
        selected_model = OpenStruct.new(identifier: "advisor-model")
        advisor = OpenStruct.new(effective_llm_model: selected_model)
        account = OpenStruct.new(default_llm_model: OpenStruct.new(identifier: "account-default"), llm_models: OpenStruct.new(enabled: [ OpenStruct.new(identifier: "fallback") ]))
        conversation = OpenStruct.new(account: account, space: nil, council: nil, user: nil)

        context = ConversationContext.new(conversation: conversation, advisor: advisor)
        assert_equal selected_model, context.model
      end

      test "model falls back from account default to enabled first" do
        fallback_model = OpenStruct.new(identifier: "fallback")
        account = OpenStruct.new(default_llm_model: nil, llm_models: OpenStruct.new(enabled: [ fallback_model ]))
        conversation = OpenStruct.new(account: account, space: nil, council: nil, user: nil)

        context = ConversationContext.new(conversation: conversation)
        assert_equal fallback_model, context.model
      end

      test "initialize falls back account from advisor when conversation account missing" do
        advisor_account = OpenStruct.new(default_llm_model: OpenStruct.new(identifier: "advisor-default"), llm_models: OpenStruct.new(enabled: []))
        advisor = OpenStruct.new(account: advisor_account, effective_llm_model: nil, scribe?: false)
        conversation = OpenStruct.new(account: nil, space: nil, council: nil, user: nil)

        context = ConversationContext.new(conversation: conversation, advisor: advisor)

        assert_equal advisor_account, context.account
        assert_equal "advisor-default", context.model.identifier
      end

      test "model returns nil when advisor and account models are unavailable" do
        account = OpenStruct.new(default_llm_model: nil, llm_models: OpenStruct.new(enabled: []))
        advisor = OpenStruct.new(effective_llm_model: nil)
        conversation = OpenStruct.new(account: account, space: nil, council: nil, user: nil)

        context = ConversationContext.new(conversation: conversation, advisor: advisor)

        assert_nil context.model
      end

      test "initialize prefers explicit account over conversation and advisor accounts" do
        explicit = OpenStruct.new(default_llm_model: OpenStruct.new(identifier: "explicit"), llm_models: OpenStruct.new(enabled: []))
        conversation_account = OpenStruct.new(default_llm_model: OpenStruct.new(identifier: "conversation"), llm_models: OpenStruct.new(enabled: []))
        advisor_account = OpenStruct.new(default_llm_model: OpenStruct.new(identifier: "advisor"), llm_models: OpenStruct.new(enabled: []))
        advisor = OpenStruct.new(account: advisor_account, effective_llm_model: nil, scribe?: false)
        conversation = OpenStruct.new(account: conversation_account, space: nil, council: nil, user: nil)

        context = ConversationContext.new(conversation: conversation, advisor: advisor, account: explicit)

        assert_equal explicit, context.account
        assert_equal "explicit", context.model.identifier
      end

      test "model safely returns nil when account has no llm_models collection" do
        account = OpenStruct.new(default_llm_model: nil, llm_models: nil)
        advisor = OpenStruct.new(effective_llm_model: nil)
        conversation = OpenStruct.new(account: account, space: nil, council: nil, user: nil)

        context = ConversationContext.new(conversation: conversation, advisor: advisor)

        assert_nil context.model
      end
    end
  end
end
