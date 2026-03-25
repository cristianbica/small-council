# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class KickCommandTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "validate requires advisor argument" do
        command = KickCommand.new([])

        assert_equal false, command.valid?
        assert_includes command.errors, "Usage: /kick advisor-name"
      end

      test "execute removes advisor participant and adds info message" do
        advisor = advisors(:two)

        assert_difference "@conversation.conversation_participants.count", -1 do
          assert_difference "@conversation.messages.where(message_type: :info).count", 1 do
            result = KickCommand.new([ advisor.name ]).execute(conversation: @conversation, user: @user)
            assert_equal true, result[:success]
          end
        end

        info_message = @conversation.messages.where(message_type: :info).order(:id).last
        assert_equal "#{@user.display_name} removed #{advisor.name}", info_message.content
      end

      test "execute rejects missing advisor" do
        result = KickCommand.new([ "missing-advisor" ]).execute(conversation: @conversation, user: @user)

        assert_equal false, result[:success]
        assert_match(/not found/, result[:message])
      end
    end
  end
end
