# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class MemoriesCommandTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "validate rejects arguments" do
        command = MemoriesCommand.new([ "extra" ])

        assert_equal false, command.valid?
        assert_includes command.errors, "Usage: /memories"
      end

      test "execute returns memories for conversation space" do
        result = MemoriesCommand.new([]).execute(conversation: @conversation, user: @user)

        assert_equal true, result[:success]
        assert result[:memories].all? { |memory| memory.space_id == @conversation.space_id }
      end
    end
  end
end
