# frozen_string_literal: true

require "test_helper"

module AI
  module Commands
    class BaseCommandTest < ActiveSupport::TestCase
      class ValidCommand < BaseCommand
        protected

        def validate
        end
      end

      class InvalidCommand < BaseCommand
        protected

        def validate
          errors << "invalid"
        end
      end

      class NoValidateCommand < BaseCommand
      end

      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @user = users(:one)
      end

      test "valid? is true when no validation errors are added" do
        assert_equal true, ValidCommand.new([]).valid?
      end

      test "valid? is false when validate appends errors" do
        command = InvalidCommand.new([])

        assert_equal false, command.valid?
        assert_includes command.errors, "invalid"
      end

      test "valid? raises when validate is not implemented" do
        assert_raises(NotImplementedError) { NoValidateCommand.new([]).valid? }
      end

      test "execute raises not implemented by default" do
        assert_raises(NotImplementedError) { ValidCommand.new([]).execute(conversation: nil, user: nil) }
      end

      test "normalized_advisor_name accepts bare and mentioned handles" do
        command = ValidCommand.new([])

        assert_equal "fixture-counselor-one", command.send(:normalized_advisor_name, "fixture-counselor-one")
        assert_equal "fixture-counselor-one", command.send(:normalized_advisor_name, "@fixture-counselor-one")
      end

      test "normalized_advisor_name rejects invalid handles" do
        command = ValidCommand.new([])

        assert_nil command.send(:normalized_advisor_name, "not valid")
        assert_nil command.send(:normalized_advisor_name, "advisor!")
      end

      test "create_info_message creates system info message from user" do
        command = ValidCommand.new([])

        assert_difference "@conversation.messages.count", 1 do
          command.send(:create_info_message!, conversation: @conversation, user: @user, content: "user added fixture-counselor-one")
        end

        message = @conversation.messages.order(:id).last
        assert_equal "info", message.message_type
        assert_equal "system", message.role
        assert_equal @user, message.sender
      end
    end
  end
end
