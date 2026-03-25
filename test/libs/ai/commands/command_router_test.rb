# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class CommandRouterTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "parse returns nil for non-command text" do
        assert_nil CommandRouter.parse("hello")
      end

      test "parse extracts command and args" do
        parsed = CommandRouter.parse("/attach 1")

        assert_equal "attach", parsed[:command]
        assert_equal [ "1" ], parsed[:args]
      end

      test "execute returns nil for non-command text" do
        assert_nil CommandRouter.execute(content: "hello", conversation: @conversation, user: @user)
      end

      test "execute returns unknown command list including attach" do
        result = CommandRouter.execute(content: "/unknown", conversation: @conversation, user: @user)

        assert_equal false, result[:success]
        assert_match(/\/attach/, result[:message])
      end

      test "execute dispatches attach command" do
        memory = memories(:one)

        assert_difference "@conversation.messages.where(message_type: :memory_attachment).count", 1 do
          result = CommandRouter.execute(content: "/attach #{memory.id}", conversation: @conversation, user: @user)
          assert_equal true, result[:success]
          assert_equal "attach", result[:action]
        end
      end
    end
  end
end
