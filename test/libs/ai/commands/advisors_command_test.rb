# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class AdvisorsCommandTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "validate rejects arguments" do
        command = AdvisorsCommand.new([ "extra" ])

        assert_equal false, command.valid?
        assert_includes command.errors, "Usage: /advisors"
      end

      test "execute returns scoped advisors" do
        result = AdvisorsCommand.new([]).execute(conversation: @conversation, user: @user)

        assert_equal true, result[:success]
        assert result[:advisors].all? { |advisor| advisor.space_id == @conversation.space_id }
      end
    end
  end
end
