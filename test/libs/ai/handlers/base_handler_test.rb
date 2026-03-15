# frozen_string_literal: true

require "test_helper"

module AI
  module Handlers
    class BaseHandlerTest < ActiveSupport::TestCase
      class TestHandler < BaseHandler
        attr_reader :handled_result

        def handle(result)
          @handled_result = result
        end
      end

      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @context = AI::Contexts::SpaceContext.new(
          account: @account,
          space: @space
        )
      end

      test "initialize stores task and context" do
        task = mock("task")

        handler = TestHandler.new(task: task, context: @context)

        assert_equal task, handler.task
        assert_equal @context, handler.context
      end

      test "initialize with minimal arguments" do
        handler = TestHandler.new

        assert_nil handler.task
        assert_nil handler.context
      end

      test "handle raises NotImplementedError in base class" do
        handler = BaseHandler.new

        assert_raises(NotImplementedError) do
          handler.handle(nil)
        end
      end

      test "subclass can implement handle" do
        handler = TestHandler.new
        result = AI::Result.new

        handler.handle(result)

        assert_equal result, handler.handled_result
      end
    end
  end
end
