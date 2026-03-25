# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class InviteCommandTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "validate requires advisor argument" do
        command = InviteCommand.new([])

        assert_equal false, command.valid?
        assert_includes command.errors, "Usage: /invite advisor-name"
      end

      test "validate enforces advisor format" do
        command = InviteCommand.new([ "advisor!" ])

        assert_equal false, command.valid?
        assert_includes command.errors, "Please provide an advisor name like advisor-name"
      end

      test "execute adds advisor participant and info message" do
        advisor = @account.advisors.create!(
          space: @conversation.space,
          name: "new-advisor",
          system_prompt: "new",
          is_scribe: false
        )

        assert_difference ["@conversation.conversation_participants.count", "@conversation.messages.where(message_type: :info).count"], 1 do
          result = InviteCommand.new([ advisor.name ]).execute(conversation: @conversation, user: @user)
          assert_equal true, result[:success]
        end

        info_message = @conversation.messages.where(message_type: :info).order(:id).last
        assert_equal "#{@user.display_name} added #{advisor.name}", info_message.content
      end

      test "execute rejects already participating advisor" do
        result = InviteCommand.new([ advisors(:one).name ]).execute(conversation: @conversation, user: @user)

        assert_equal false, result[:success]
        assert_match(/already in this conversation/, result[:message])
      end
    end
  end
end
