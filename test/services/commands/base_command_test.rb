# frozen_string_literal: true

require "test_helper"

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
  end
end
