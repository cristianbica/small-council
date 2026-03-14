# frozen_string_literal: true

class AI::Client::Chat
  attr_reader :provider, :model, :messages

  def initialize(provider:, model:)
    @provider = provider
    @model = model
    @messages = []
    @trackers = []
    @tools = []
    @callbacks = {
      before_message: [],
      after_message: [],
      before_tool_call: [],
      after_tool_call: []
    }
    @pending_tool_call = nil
  end

  def before_message(&block)
    @callbacks[:before_message] << block
    self
  end

  def after_message(&block)
    @callbacks[:after_message] << block
    self
  end

  def before_tool_call(&block)
    @callbacks[:before_tool_call] << block
    self
  end

  def after_tool_call(&block)
    @callbacks[:after_tool_call] << block
    self
  end

  def add_message(role: :user, content: nil, **extra)
    messages << { role: role, content: content, **extra }.compact
    self
  end

  def instructions(text)
    add_message(role: :system, content: text)
  end

  def schema(schema)
    @schema = schema
  end

  def register_tracker(tracker)
    @trackers << tracker
    self
  end

  def tools(tool_instances)
    @tools.concat(Array(tool_instances))
    self
  end

  def complete(result)
    chat = provider.chat(model: model.identifier)
    @tools.each { |tool| chat.with_tools(tool) }
    messages.select { |m| m[:role] == :system }.each { |m| chat.add_message(m) }
    messages.select { |m| m[:role] != :system }.each { |m| chat.add_message(m) }
    chat.with_schema(@schema) if @schema
    @trackers.each { |tracker| tracker.register(self) }
    wire_rubyllm_events(chat)
    result.response = chat.complete
  rescue StandardError => e
    # Log detailed error information for debugging provider issues
    Rails.logger.error("[AI Client] Provider error: #{e.class} - #{e.message}")
    Rails.logger.error("[AI Client] Model: #{model.identifier}, Messages count: #{messages.count}")
    Rails.logger.error("[AI Client] Backtrace: #{e.backtrace.first(5).join("; ")}")
    raise
  end

  private

  def wire_rubyllm_events(chat)
    chat.on_new_message do
      run_callbacks(:before_message)
    end

    chat.on_end_message do |response|
      run_callbacks(:after_message, response)
    end

    chat.on_tool_call do |tool_call|
      @pending_tool_call = tool_call
      run_callbacks(:before_tool_call, tool_call)
    end

    chat.on_tool_result do |result|
      tool_call = @pending_tool_call
      @pending_tool_call = nil
      run_callbacks(:after_tool_call, tool_call, result) if tool_call
    end
  end

  def run_callbacks(event, *args)
    @callbacks[event]&.each { |callback| callback.call(*args) }
  end
end
