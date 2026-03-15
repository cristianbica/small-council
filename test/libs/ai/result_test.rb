# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class ResultTest < ActiveSupport::TestCase
    test "initialize creates empty result" do
      result = AI::Result.new
      assert_nil result.response
      assert_nil result.error
    end

    test "content returns response content when no error" do
      result = AI::Result.new
      result.response = OpenStruct.new(content: "Hello world")

      assert_equal "Hello world", result.content
    end

    test "content returns error message when error present" do
      result = AI::Result.new
      result.error = StandardError.new("Something went wrong")

      assert_equal "Error: Something went wrong", result.content
    end

    test "content returns manually set content" do
      result = AI::Result.new
      result.content = "Manual content"

      assert_equal "Manual content", result.content
    end

    test "content returns nil when nothing set" do
      result = AI::Result.new
      assert_nil result.content
    end

    test "success? returns true when no error and content present" do
      result = AI::Result.new
      result.response = OpenStruct.new(content: "Success")

      assert result.success?
      assert_not result.failure?
    end

    test "success? returns false when error present" do
      result = AI::Result.new
      result.error = StandardError.new("Error")

      assert_not result.success?
      assert result.failure?
    end

    test "success? returns false when content is blank" do
      result = AI::Result.new
      result.response = OpenStruct.new(content: "")

      assert_not result.success?
      assert result.failure?
    end

    test "failure? returns true when content is nil" do
      result = AI::Result.new

      assert result.failure?
      assert_not result.success?
    end

    test "delegates methods to response" do
      result = AI::Result.new
      result.response = OpenStruct.new(content: "test", custom_method: "custom")

      # Should delegate custom_method to response
      assert_equal "custom", result.custom_method
    end

    test "response setter updates response object" do
      result = AI::Result.new
      response = OpenStruct.new(content: "New response")
      result.response = response

      assert_equal response, result.response
      assert_equal "New response", result.content
    end

    test "error setter updates error object" do
      result = AI::Result.new
      error = StandardError.new("Test error")
      result.error = error

      assert_equal error, result.error
      assert_equal "Error: Test error", result.content
    end
  end
end
