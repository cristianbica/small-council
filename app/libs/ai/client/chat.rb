# frozen_string_literal: true

class AI::Client::Chat
  attr_reader :provider, :model, :messages

  def initialize(provider:, model:)
    @provider = provider
    @model = model
    @messages = []
    @trackers = []
    @tools = []
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
    @trackers.each { |tracker| tracker.register(chat) }
    result.response = chat.complete
  end
end
