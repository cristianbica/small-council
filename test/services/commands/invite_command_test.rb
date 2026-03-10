# frozen_string_literal: true

require "test_helper"
require "ostruct"

module Commands
  class InviteCommandTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)
      @conversation = conversations(:one)
      @user = users(:one)
    end

    test "validate requires mention argument" do
      command = InviteCommand.new([])

      assert_equal false, command.valid?
      assert_includes command.errors, "Usage: /invite @advisor-name"
    end

    test "validate enforces advisor mention format" do
      command = InviteCommand.new([ "advisor" ])

      assert_equal false, command.valid?
      assert_includes command.errors, "Please mention an advisor with @advisor-name"
    end

    test "execute returns error when conversation has no space" do
      conversation = OpenStruct.new(space_id: nil)
      result = InviteCommand.new([ "@fixture-counselor-one" ]).execute(conversation: conversation, user: @user)

      assert_equal false, result[:success]
      assert_match(/space is required/, result[:message])
    end

    test "execute returns not found when advisor does not exist" do
      result = InviteCommand.new([ "@missing-advisor" ]).execute(conversation: @conversation, user: @user)

      assert_equal false, result[:success]
      assert_match(/not found/, result[:message])
    end

    test "execute rejects scribe advisor" do
      scribe = @account.advisors.create!(
        space: @conversation.space,
        name: "scribe-test",
        system_prompt: "scribe",
        is_scribe: true
      )

      result = InviteCommand.new([ "@#{scribe.name}" ]).execute(conversation: @conversation, user: @user)

      assert_equal false, result[:success]
      assert_match(/automatically present/, result[:message])
    end

    test "execute rejects already participating advisor" do
      result = InviteCommand.new([ "@fixture-counselor-one" ]).execute(conversation: @conversation, user: @user)

      assert_equal false, result[:success]
      assert_match(/already in this conversation/, result[:message])
    end

    test "execute adds advisor to conversation participants" do
      advisor = @account.advisors.create!(
        space: @conversation.space,
        name: "new-advisor",
        system_prompt: "new",
        is_scribe: false
      )

      assert_difference "@conversation.conversation_participants.count", 1 do
        result = InviteCommand.new([ "@#{advisor.name}" ]).execute(conversation: @conversation, user: @user)
        assert_equal true, result[:success]
      end
    end

    test "execute returns error payload when create fails" do
      advisor = @account.advisors.create!(
        space: @conversation.space,
        name: "failing-advisor",
        system_prompt: "new",
        is_scribe: false
      )

      relation = @conversation.conversation_participants
      relation.stubs(:maximum).returns(1)
      relation.stubs(:create!).raises(StandardError.new("db-error"))

      result = InviteCommand.new([ "@#{advisor.name}" ]).execute(conversation: @conversation, user: @user)

      assert_equal false, result[:success]
      assert_match(/Error inviting advisor: db-error/, result[:message])
    end
  end
end
