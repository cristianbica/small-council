# frozen_string_literal: true

module AI
  class Runner
    attr_reader :task, :context, :handler, :trackers

    def self.run(task:, context:, handler: nil, tracker: nil, async: false)
      return async(task:, context:, handler:, tracker:) if async

      new(task:, context:, handler:, tracker:).run
    end

    def self.async(task:, context:, handler: nil, tracker: nil)
      AIRunnerJob.perform_later(task:, context:, handler:, tracker:)
    end

    def initialize(task:, context:, handler: nil, tracker: nil)
      @context = build_context(context)
      @task = build_task(task)
      @handler = build_handler(handler)
      @trackers = build_trackers(tracker)
    end

    def run
      raise AI::ResolutionError, "Task must respond to #run" unless task.respond_to?(:run)

      result = AI::Result.new

      task.run(result, trackers: trackers)
      track(result)
      handle(result)

      result
    rescue StandardError => e
      raise unless handler
      Rails.logger.error("Error running AI task #{task.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      result ||= AI::Result.new
      result.error = e
      handle(result)
      result
    end

    private

    def build_context(value)
      return value if value.is_a?(AI::Contexts::BaseContext)

      type, args = value.is_a?(Hash) ? [ value[:type], value.except(:type) ] : [ value, {} ]
      klass = AI.context(type)
      raise AI::ResolutionError, "Unknown context: #{type}" unless klass
      klass.new(**args)
    end

    def build_task(value)
      return value if value.is_a?(AI::Tasks::BaseTask)

      type, args = value.is_a?(Hash) ? [ value[:type], value.except(:type) ] : [ value, {} ]
      klass = AI.task(type)
      raise AI::ResolutionError, "Unknown task: #{type}" unless klass
      klass.new(context:, **args)
    end

    def build_handler(value)
      return nil if value.nil?
      return value if value.is_a?(AI::Handlers::BaseHandler)

      type, args = value.is_a?(Hash) ? [ value[:type], value.except(:type) ] : [ value, {} ]
      klass = AI.handler(type)
      raise AI::ResolutionError, "Unknown handler: #{type}" unless klass
      klass.new(task:, context:, **args)
    end

    def build_trackers(value)
      trackers = [
        AI::Trackers::UsageTracker.new(task:, context:),
        AI::Trackers::VersionsTracker.new(task:, context:)
      ]
      return trackers if value.nil?

      trackers << build_tracker(value)
      trackers.uniq
    end

    def build_tracker(value)
      return value if !value.is_a?(Class) && value.respond_to?(:track)

      type, = value.is_a?(Hash) ? [ value[:type], value.except(:type) ] : [ value, {} ]
      klass = AI.tracker(type)
      raise AI::ResolutionError, "Unknown tracker: #{type}" unless klass

      klass.new(task:, context:)
    end

    def track(result)
      trackers.each do |tracker|
        tracker.track(result)
      end
    end

    def handle(result)
      handler.handle(result) if handler
    end
  end
end
