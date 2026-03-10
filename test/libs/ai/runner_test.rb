# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class RunnerTest < ActiveSupport::TestCase
    class FakeContext < AI::Contexts::BaseContext
      attr_reader :model

      def initialize(model: OpenStruct.new(identifier: "m"), **args)
        super(**args)
        @model = model
      end
    end

    class FakeTask < AI::Tasks::BaseTask
      def run(result, trackers: [])
        result.response = OpenStruct.new(content: "ok")
        trackers.each { |tracker| tracker.register(OpenStruct.new) if tracker.respond_to?(:register) }
        result
      end
    end

    class BadTask
      def initialize(*); end
    end

    class FakeHandler < AI::Handlers::BaseHandler
      attr_reader :handled

      def handle(result)
        @handled = result
      end
    end

    class BoomTask < AI::Tasks::BaseTask
      def run(_result, trackers: [])
        raise StandardError, "boom"
      end
    end

    class FakeTracker
      attr_reader :tracked

      def initialize(*); end

      def track(result)
        @tracked = result
      end
    end

    class ContextWithArgs < AI::Contexts::BaseContext
      attr_reader :marker

      def initialize(marker: nil, **args)
        super(**args)
        @marker = marker
      end

      def model
        OpenStruct.new(identifier: "model")
      end
    end

    class TaskWithArgs < AI::Tasks::BaseTask
      attr_reader :marker

      def initialize(context:, marker: nil)
        super(context: context)
        @marker = marker
      end

      def prepare(_chat); end
    end

    class HandlerWithArgs < AI::Handlers::BaseHandler
      attr_reader :marker

      def initialize(task:, context:, marker: nil)
        super(task: task, context: context)
        @marker = marker
      end
    end

    class TrackableClass
      def initialize(*); end

      def track(_result); end
    end

    test "run returns task result and tracks with default usage tracker" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)

      runner = AI::Runner.new(task: :x, context: :y)
      result = runner.run

      assert_equal "ok", result.content
      assert runner.trackers.any? { |t| t.is_a?(AI::Trackers::UsageTracker) }
    end

    test "class run dispatches async and sync modes" do
      AI::Runner.expects(:async).with(task: :t, context: :c, handler: nil, tracker: nil).returns(:job)
      assert_equal :job, AI::Runner.run(task: :t, context: :c, async: true)

      fake = mock("runner")
      AI::Runner.expects(:new).with(task: :t, context: :c, handler: nil, tracker: nil).returns(fake)
      fake.expects(:run).returns(:done)
      assert_equal :done, AI::Runner.run(task: :t, context: :c, async: false)
    end

    test "async enqueues job" do
      AIRunnerJob.expects(:perform_later).with(task: :t, context: :c, handler: :h, tracker: :tr).returns(:enqueued)
      assert_equal :enqueued, AI::Runner.async(task: :t, context: :c, handler: :h, tracker: :tr)
    end

    test "run raises when task does not respond to run" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(BadTask)
      runner = AI::Runner.new(task: :x, context: :y)

      assert_raises(AI::ResolutionError) { runner.run }
    end

    test "run handles task errors when handler is provided" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(BoomTask)
      AI.stubs(:handler).returns(FakeHandler)
      Rails.logger.stubs(:error)

      runner = AI::Runner.new(task: :x, context: :y, handler: :z)
      result = runner.run

      assert result.failure?
      assert_match(/boom/, result.content)
    end

    test "run re-raises task errors without handler" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(BoomTask)
      runner = AI::Runner.new(task: :x, context: :y)

      assert_raises(StandardError) { runner.run }
    end

    test "build_tracker accepts tracker object and hash type" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)
      AI.stubs(:tracker).with(:usage).returns(FakeTracker)

      direct = FakeTracker.new
      runner_with_object = AI::Runner.new(task: :x, context: :y, tracker: direct)
      assert_includes runner_with_object.trackers, direct

      runner_with_hash = AI::Runner.new(task: :x, context: :y, tracker: { type: :usage })
      assert runner_with_hash.trackers.any? { |t| t.is_a?(FakeTracker) }
    end

    test "build_context accepts a context instance directly" do
      context = FakeContext.new
      AI.stubs(:task).returns(FakeTask)

      runner = AI::Runner.new(task: :x, context: context)

      assert_same context, runner.context
    end

    test "build_context builds from hash and raises for unknown type" do
      AI.stubs(:context).with(:fake).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)

      runner = AI::Runner.new(task: :x, context: { type: :fake, marker: 1 })
      assert_instance_of FakeContext, runner.context
      assert_equal 1, runner.context[:marker]

      AI.stubs(:context).with(:missing).returns(nil)
      error = assert_raises(AI::ResolutionError) do
        AI::Runner.new(task: :x, context: :missing)
      end
      assert_match(/Unknown context: missing/, error.message)
    end

    test "build_task accepts a task instance and raises for unknown task" do
      AI.stubs(:context).returns(FakeContext)
      task = FakeTask.new(context: FakeContext.new)

      runner = AI::Runner.new(task: task, context: :y)
      assert_same task, runner.task

      AI.stubs(:task).with(:missing).returns(nil)
      error = assert_raises(AI::ResolutionError) do
        AI::Runner.new(task: :missing, context: :y)
      end
      assert_match(/Unknown task: missing/, error.message)
    end

    test "build_handler supports nil instance hash and unknown" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)

      no_handler = AI::Runner.new(task: :x, context: :y, handler: nil)
      assert_nil no_handler.handler

      instance = FakeHandler.new(task: no_handler.task, context: no_handler.context)
      with_instance = AI::Runner.new(task: :x, context: :y, handler: instance)
      assert_same instance, with_instance.handler

      AI.stubs(:handler).with(:fake).returns(FakeHandler)
      with_hash = AI::Runner.new(task: :x, context: :y, handler: { type: :fake })
      assert_instance_of FakeHandler, with_hash.handler

      AI.stubs(:handler).with(:missing).returns(nil)
      error = assert_raises(AI::ResolutionError) do
        AI::Runner.new(task: :x, context: :y, handler: :missing)
      end
      assert_match(/Unknown handler: missing/, error.message)
    end

    test "build_tracker supports class type and raises for unknown type" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)
      AI.stubs(:tracker).with(:classy).returns(TrackableClass)

      runner = AI::Runner.new(task: :x, context: :y, tracker: :classy)
      assert runner.trackers.any? { |t| t.is_a?(TrackableClass) }

      AI.stubs(:tracker).with(:missing).returns(nil)
      error = assert_raises(AI::ResolutionError) do
        AI::Runner.new(task: :x, context: :y, tracker: :missing)
      end
      assert_match(/Unknown tracker: missing/, error.message)
    end

    test "run invokes handler for successful results" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)
      AI.stubs(:handler).returns(FakeHandler)

      runner = AI::Runner.new(task: :x, context: :y, handler: :h)
      result = runner.run

      assert_same result, runner.handler.handled
      assert_equal "ok", result.content
    end

    test "build_context task and handler pass hash args to constructors" do
      AI.stubs(:context).with(:ctx).returns(ContextWithArgs)
      AI.stubs(:task).with(:tsk).returns(TaskWithArgs)
      AI.stubs(:handler).with(:hdl).returns(HandlerWithArgs)

      runner = AI::Runner.new(
        task: { type: :tsk, marker: "task-mark" },
        context: { type: :ctx, marker: "context-mark", extra: 1 },
        handler: { type: :hdl, marker: "handler-mark" }
      )

      assert_equal "context-mark", runner.context.marker
      assert_equal 1, runner.context[:extra]
      assert_equal "task-mark", runner.task.marker
      assert_equal "handler-mark", runner.handler.marker
    end

    test "build_trackers removes duplicates when same tracker object is provided" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)

      usage_tracker = AI::Trackers::UsageTracker.new(task: nil, context: nil)
      AI::Trackers::UsageTracker.stubs(:new).returns(usage_tracker)

      runner = AI::Runner.new(task: :x, context: :y, tracker: usage_tracker)

      assert_equal 1, runner.trackers.count { |t| t.equal?(usage_tracker) }
    end

    test "run tracks with every tracker" do
      AI.stubs(:context).returns(FakeContext)
      AI.stubs(:task).returns(FakeTask)

      custom = FakeTracker.new
      runner = AI::Runner.new(task: :x, context: :y, tracker: custom)

      result = runner.run

      assert_same result, custom.tracked
      assert runner.trackers.any? { |t| t.is_a?(AI::Trackers::UsageTracker) }
    end
  end
end
