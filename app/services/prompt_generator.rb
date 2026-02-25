class PromptGenerator
  class Error < StandardError; end
  class NoModelError < Error; end
  class NoFreeModelError < NoModelError; end  # Backwards compatibility
  class GenerationError < Error; end

  # System prompt for generating advisor prompts
  PROMPT_GENERATOR_SYSTEM_PROMPT = <<~PROMPT
    You are an expert at creating system prompts for AI advisors.#{' '}
    Given a short description of an advisor's role, generate a comprehensive system prompt that:
    - Defines the advisor's personality and expertise
    - Specifies how they should respond to users
    - Sets clear boundaries and tone
    - Includes relevant context for their domain

    The prompt should be 2-4 paragraphs, professional, and actionable.
    Only return the system prompt text, no additional commentary.
  PROMPT

  def self.generate(description:, account:)
    new(description: description, account: account).generate
  end

  def initialize(description:, account:)
    @description = description
    @account = account
  end

  def generate
    model = find_suitable_model
    raise NoModelError, "No AI model available. Please configure a default model or enable a free model in AI Providers." unless model

    user_prompt = build_user_prompt

    result = model.api.chat(
      [ { role: "user", content: user_prompt } ],
      system_prompt: PROMPT_GENERATOR_SYSTEM_PROMPT,
      temperature: 0.7,
      max_tokens: 1500
    )

    result&.[](:content) || raise(GenerationError, "Failed to generate prompt")
  rescue NoModelError
    raise  # Re-raise our own errors
  rescue LLM::APIError => e
    Rails.logger.error "[PromptGenerator] API error: #{e.message}"
    raise GenerationError, "AI API error: #{e.message}"
  rescue GenerationError
    raise  # Re-raise our own errors
  rescue => e
    Rails.logger.error "[PromptGenerator] Error: #{e.message}"
    raise GenerationError, "Failed to generate prompt: #{e.message}"
  end

  private

  def find_suitable_model
    # Prefer account's default model, then fall back to free model
    @account.default_llm_model&.enabled? ? @account.default_llm_model : @account.llm_models.enabled.free.first
  end

  def build_user_prompt
    <<~PROMPT
      Create a system prompt for an AI advisor with the following description:

      "#{@description}"

      The advisor should be helpful, professional, and focused on their area of expertise.
    PROMPT
  end
end
