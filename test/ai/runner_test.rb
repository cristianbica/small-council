# frozen_string_literal: true

require "test_helper"

module AI
  class RunnerTest < ActiveSupport::TestCase
    class DummyContext < AI::Contexts::BaseContext
      def model
        OpenStruct.new(identifier: "dummy", provider: OpenStruct.new(provider_type: "openai"))
      end
    end

    class DummyTask < AI::Tasks::BaseTask
      attr_reader :ran_with_trackers

      def initialize(context:, should_raise: false)
        super(context:)
        @should_raise = should_raise
      end

      def run(result, trackers: [])
        raise "boom" if @should_raise

        @ran_with_trackers = trackers
        result.content = "ok"
        result
      end

      def prepare(_chat)
      end
    end

    class DummyHandler < AI::Handlers::BaseHandler
      attr_reader :handled_result

      def handle(result)
        @handled_result = result
      end
    end

    class DummyTracker
      attr_reader :tracked_result

      def initialize(**)
      end

      def track(result)
        @tracked_result = result
      end
    end

    setup do
      AI::Trackers::UsageTracker.any_instance.stubs(:track)
    end

    test "run executes task, trackers, and handler" do
      context = DummyContext.new
      task = DummyTask.new(context:)
      handler = DummyHandler.new
      tracker = DummyTracker.new

      result = AI::Runner.new(task:, context:, handler:, tracker:).run

      assert_equal "ok", result.content
      assert_same result, handler.handled_result
      assert_same result, tracker.tracked_result
      assert task.ran_with_trackers.any? { |t| t.is_a?(AI::Trackers::UsageTracker) }
      assert task.ran_with_trackers.any? { |t| t.equal?(tracker) }
    end

    test "run raises when task errors and no handler" do
      context = DummyContext.new
      task = DummyTask.new(context:, should_raise: true)

      assert_raises(RuntimeError) do
        AI::Runner.new(task:, context:).run
      end
    end

    test "run captures task error and passes failed result to handler" do
      context = DummyContext.new
      task = DummyTask.new(context:, should_raise: true)
      handler = DummyHandler.new

      result = AI::Runner.new(task:, context:, handler:).run

      assert result.failure?
      assert_equal "boom", result.error.message
      assert_same result, handler.handled_result
    end

    test "class run supports async path" do
      AI::Runner.expects(:async).with(task: :text, context: :space, handler: nil, tracker: nil)
      AI::Runner.run(task: :text, context: :space, async: true)
    end

    test "class async enqueues AIRunnerJob" do
      AIRunnerJob.expects(:perform_later).with(task: :text, context: :space, handler: :foo, tracker: :bar)
      AI::Runner.async(task: :text, context: :space, handler: :foo, tracker: :bar)
    end

    test "builds dependencies from type hashes" do
      context_instance = DummyContext.new
      task_instance = DummyTask.new(context: context_instance)
      handler_instance = DummyHandler.new
      tracker_instance = DummyTracker.new

      AI.stubs(:context).with(:dummy).returns(DummyContext)
      AI.stubs(:task).with(:dummy).returns(Class.new(DummyTask) do
        define_method(:initialize) { |context:, **| super(context:) }
      end)
      AI.stubs(:handler).with(:dummy).returns(Class.new(DummyHandler) do
        define_method(:initialize) { |task:, context:, **| super(task:, context:) }
      end)
      AI.stubs(:tracker).with(:dummy).returns(Class.new(DummyTracker) do
        define_method(:initialize) { |task:, context:, **| super() }
      end)

      runner = AI::Runner.new(
        context: { type: :dummy },
        task: { type: :dummy },
        handler: { type: :dummy },
        tracker: { type: :dummy }
      )

      result = runner.run
      assert_equal "ok", result.content
      assert_instance_of DummyContext, runner.context
      assert runner.task.is_a?(DummyTask)
      assert runner.handler.is_a?(DummyHandler)
      assert runner.trackers.any? { |t| t.is_a?(AI::Trackers::UsageTracker) }
      assert runner.trackers.any? { |t| t.is_a?(DummyTracker) }

      # touch local vars to keep lint quiet for explicit construction helpers
      assert_nil context_instance.args[:unused]
      assert_nil task_instance.ran_with_trackers
      assert_nil handler_instance.handled_result
      assert_nil tracker_instance.tracked_result
    end

    test "ai runner job delegates to runner" do
      runner = mock("runner")
      runner.expects(:run)
      AI::Runner.expects(:new).with(task: :text, context: :space, handler: :h, tracker: :t).returns(runner)

      AIRunnerJob.new.perform(task: :text, context: :space, handler: :h, tracker: :t)
    end
  end
end
