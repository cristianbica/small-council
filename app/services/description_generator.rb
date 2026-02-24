class DescriptionGenerator
  class Error < StandardError; end
  class NoFreeModelError < Error; end
  class GenerationError < Error; end

  # System prompt for generating council descriptions
  DESCRIPTION_GENERATOR_SYSTEM_PROMPT = <<~PROMPT
    You are an expert at creating compelling descriptions for AI advisor councils.
    Given a council name, generate a concise, professional description (1-2 sentences)
    that explains what the council does and how it helps users.

    The description should be:
    - Clear and engaging
    - Specific about the council's purpose
    - Action-oriented (explains what users can accomplish)
    - Under 200 characters if possible

    Only return the description text, no additional commentary or quotes.
  PROMPT

  def self.generate(name:, account:)
    new(name: name, account: account).generate
  end

  def initialize(name:, account:)
    @name = name
    @account = account
  end

  def generate
    free_model = find_free_model
    raise NoFreeModelError, "No free AI model available. Please configure a free model in AI Providers." unless free_model

    user_prompt = build_user_prompt

    result = free_model.api.chat(
      [ { role: "user", content: user_prompt } ],
      system_prompt: DESCRIPTION_GENERATOR_SYSTEM_PROMPT,
      temperature: 0.7,
      max_tokens: 500
    )

    result&.[](:content)&.strip || raise(GenerationError, "Failed to generate description")
  rescue NoFreeModelError
    raise
  rescue LLM::APIError => e
    Rails.logger.error "[DescriptionGenerator] API error: #{e.message}"
    raise GenerationError, "AI API error: #{e.message}"
  rescue GenerationError
    raise
  rescue => e
    Rails.logger.error "[DescriptionGenerator] Error: #{e.message}"
    raise GenerationError, "Failed to generate description: #{e.message}"
  end

  private

  def find_free_model
    @account.llm_models.enabled.free.first
  end

  def build_user_prompt
    <<~PROMPT
      Create a compelling description for an AI advisor council named:

      "#{@name}"

      The description should explain what this council helps users accomplish.
    PROMPT
  end
end
