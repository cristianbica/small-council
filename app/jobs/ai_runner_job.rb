# frozen_string_literal: true

class AIRunnerJob < ApplicationJob
  queue_as :default

  def perform(task:, context:, handler: nil, tracker: nil)
    AI::Runner.new(task: task, context: context, handler: handler, tracker: tracker).run
  end
end
