module AI
  class ResolutionError < ArgumentError; end

  require "erb"

  def self.context(type)
    return type if type.is_a?(Class)

    constant = "ai/contexts/#{type}_context".classify.safe_constantize
    raise ResolutionError, "Unknown context: #{type}" unless constant

    constant
  end

  def self.task(type)
    return type if type.is_a?(Class)

    constant = "ai/tasks/#{type}_task".classify.safe_constantize
    raise ResolutionError, "Unknown task: #{type}" unless constant

    constant
  end

  def self.agent(type)
    return type if type.is_a?(Class)

    constant = "ai/agents/#{type}_agent".classify.safe_constantize
    raise ResolutionError, "Unknown agent: #{type}" unless constant

    constant
  end

  def self.handler(type)
    return type if type.is_a?(Class)

    constant = "ai/handlers/#{type}_handler".classify.safe_constantize
    raise ResolutionError, "Unknown handler: #{type}" unless constant

    constant
  end

  def self.tracker(type)
    return type if type.is_a?(Class)

    constant = "ai/trackers/#{type}_tracker".classify.safe_constantize
    raise ResolutionError, "Unknown tracker: #{type}" unless constant

    constant
  end

  def self.prompt(type, **locals)
    path = Rails.root.join("app/libs/ai/prompts/#{type}.erb")
    raise ResolutionError, "Unknown prompt: #{type}" unless path.exist?

    ERB.new(path.read).result_with_hash(locals)
  end

  def self.schema(type)
    return type if type.is_a?(Class)

    constant = "ai/schemas/#{type}_schema".classify.safe_constantize
    raise ResolutionError, "Unknown schema: #{type}" unless constant

    constant
  end

  def self.tool(ref)
    return ref if ref.is_a?(Class)

    class_name = Tools::AbstractTool::REGISTRY[ref.to_s]
    raise ResolutionError, "Unknown tool: #{ref}" unless class_name

    klass = class_name.safe_constantize
    raise ResolutionError, "Unknown tool class: #{class_name}" unless klass

    klass
  end

  def self.tools(*refs)
    Tools::AbstractTool::REGISTRY.filter_map do |ref, class_name|
      class_name.safe_constantize if refs.any? { |tref| tref.to_s == ref || (tref.to_s.end_with?("/*") && ref.start_with?(tref.to_s.delete_suffix("/*"))) }
    end
  end

  def self.run(task:, context:, handler: nil, tracker: nil, async: false)
    Runner.run(task: task, context: context, handler: handler, tracker: tracker, async: async)
  end

  def self.generate_text(description:, prompt:, schema: nil, space:, handler: nil, async: false, **args)
    Runner.run(
      task: {
        type: :text,
        prompt: prompt,
        schema: schema,
        description: description
      },
      context: {
        type: :space,
        space: space,
        account: space&.account,
        **args
      },
      handler: handler,
      async: async
    )
  end

  def self.generate_advisor_response(advisor:, message:, prompt: nil, tracker: :model_interaction, async: true)
    AI::Runner.run(
      task: {
        type: :respond,
        prompt: prompt
      },
      context: {
        type: :conversation,
        conversation: message.conversation,
        advisor: advisor,
        message: message
      },
      handler: :conversation_response,
      tracker: tracker,
      async: async
    )
  end

  def self.runtime_for_conversation(conversation)
    case conversation.roe_type
    when "open"
      AI::Runtimes::OpenConversationRuntime.new(conversation)
    when "consensus"
      AI::Runtimes::ConsensusConversationRuntime.new(conversation)
    when "brainstorming"
      AI::Runtimes::BrainstormingConversationRuntime.new(conversation)
    else
      AI::Runtimes::OpenConversationRuntime.new(conversation)
    end
  end
end
