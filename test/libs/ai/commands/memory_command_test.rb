# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class MemoryCommandTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "validate requires one numeric argument" do
        command = MemoryCommand.new([])

        assert_equal false, command.valid?
        assert_includes command.errors, "Usage: /memory ID"

        command = MemoryCommand.new([ "abc" ])
        assert_equal false, command.valid?
        assert_includes command.errors, "Memory ID must be a number"
      end

      test "execute returns memory when found" do
        memory = memories(:one)
        result = MemoryCommand.new([ memory.id.to_s ]).execute(conversation: @conversation, user: @user)

        assert_equal true, result[:success]
        assert_equal memory, result[:memory]
      end

      test "execute returns error when not found" do
        result = MemoryCommand.new([ "999999" ]).execute(conversation: @conversation, user: @user)

        assert_equal false, result[:success]
        assert_match(/not found/, result[:message])
      end
    end
  end
end
