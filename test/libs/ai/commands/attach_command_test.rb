# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class AttachCommandTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "validate requires one numeric argument" do
        command = AttachCommand.new([])

        assert_equal false, command.valid?
        assert_includes command.errors, "Usage: /attach ID"

        command = AttachCommand.new([ "abc" ])
        assert_equal false, command.valid?
        assert_includes command.errors, "Memory ID must be a number"
      end

      test "execute creates memory attachment message" do
        memory = memories(:one)

        assert_difference "@conversation.messages.where(message_type: :memory_attachment).count", 1 do
          result = AttachCommand.new([ memory.id.to_s ]).execute(conversation: @conversation, user: @user)
          assert_equal true, result[:success]
        end

        attached = @conversation.messages.where(message_type: :memory_attachment).order(:id).last
        assert_equal "user", attached.role
        assert_equal @user, attached.sender
        assert_equal memory.id, attached.metadata["memory_id"]
        assert_equal memory.title, attached.metadata["memory_title"]
        assert_includes attached.content, memory.title
      end

      test "execute returns error when memory missing" do
        result = AttachCommand.new([ "999999" ]).execute(conversation: @conversation, user: @user)

        assert_equal false, result[:success]
        assert_match(/not found/, result[:message])
      end
    end
  end
end
