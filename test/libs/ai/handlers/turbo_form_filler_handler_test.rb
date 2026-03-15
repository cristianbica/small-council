# frozen_string_literal: true

require "test_helper"

module AI
  module Handlers
    class TurboFormFillerHandlerTest < ActiveSupport::TestCase
      include ActionCable::Channel::Broadcasting

      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @context = AI::Contexts::SpaceContext.new(
          account: @account,
          space: @space
        )
        @filler_id = "test-filler-123"
        @handler = TurboFormFillerHandler.new(
          context: @context,
          filler_id: @filler_id
        )
      end

      test "initialize stores filler_id" do
        assert_equal @filler_id, @handler.filler_id
      end

      test "handle broadcasts error on failure result" do
        result = AI::Result.new
        result.error = StandardError.new("Test error")

        Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
          "form_filler_result_#{@filler_id}",
          target: "form_filler_result_#{@filler_id}",
          partial: "form_fillers/result",
          locals: {
            filler_id: @filler_id,
            state: "error",
            payload: nil,
            error: "Test error"
          }
        )

        @handler.handle(result)
      end

      test "handle broadcasts error on blank content" do
        result = AI::Result.new
        result.response = OpenStruct.new(content: "")

        Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
          "form_filler_result_#{@filler_id}",
          target: "form_filler_result_#{@filler_id}",
          partial: "form_fillers/result",
          locals: {
            filler_id: @filler_id,
            state: "error",
            payload: nil,
            error: I18n.t("form_fillers.errors.unable_to_generate")
          }
        )

        @handler.handle(result)
      end

      test "handle broadcasts success on valid result" do
        result = AI::Result.new
        result.response = OpenStruct.new(content: { name: "John" })

        Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
          "form_filler_result_#{@filler_id}",
          target: "form_filler_result_#{@filler_id}",
          partial: "form_fillers/result",
          locals: {
            filler_id: @filler_id,
            state: "success",
            payload: '{"name":"John"}',
            error: nil
          }
        )

        @handler.handle(result)
      end

      test "handle broadcasts error on exception" do
        result = AI::Result.new
        result.response = OpenStruct.new(content: { test: "data" })

        # Force an error during JSON conversion
        result.response.stubs(:content).raises(StandardError, "JSON error")

        Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
          "form_filler_result_#{@filler_id}",
          target: "form_filler_result_#{@filler_id}",
          partial: "form_fillers/result",
          locals: {
            filler_id: @filler_id,
            state: "error",
            payload: nil,
            error: "JSON error"
          }
        )

        @handler.handle(result)
      end

      test "is a subclass of BaseHandler" do
        assert_kind_of BaseHandler, @handler
        assert @handler.is_a?(TurboFormFillerHandler)
      end
    end
  end
end
