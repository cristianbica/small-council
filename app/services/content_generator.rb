class ContentGenerator
  class Error < StandardError; end
  class NoModelError < Error; end
  class GenerationError < Error; end
  class UnknownProfileError < Error; end

  PROFILES = {
    advisor: {
      fields: [ :name, :short_description, :system_prompt ],
      system_prompt: <<~PROMPT,
        You are an expert at creating AI advisor profiles.
        Given a concept/role description, generate:
        1. name: Concise (2-4 words, professional, suitable as an identifier). Use Title Case.
        2. short_description: Brief (under 100 characters, for list views). One sentence.
        3. system_prompt: Comprehensive (2-4 paragraphs). Define personality, expertise, tone, response style, and boundaries.

        Return ONLY a valid JSON object with these exact keys: "name", "short_description", "system_prompt".
        Do not include markdown formatting, code blocks, or any text outside the JSON.
      PROMPT
      output_format: :json
    },

    council: {
      fields: [ :name, :description ],
      system_prompt: <<~PROMPT,
        You are an expert at creating compelling AI advisor councils.
        Given a concept/purpose description, generate:
        1. name: A concise, professional council name (2-5 words, Title Case). Should be descriptive and engaging.
        2. description: A compelling description (1-2 sentences, under 200 characters) that explains what the council does and how it helps users.

        The description should be:
        - Clear and engaging
        - Specific about the council's purpose
        - Action-oriented (explains what users can accomplish)

        Return ONLY a valid JSON object with these exact keys: "name", "description".
        Do not include markdown formatting, code blocks, or any text outside the JSON.
      PROMPT
      output_format: :json
    },

    conversation: {
      fields: [ :title, :initial_message ],
      system_prompt: <<~PROMPT,
        You are an expert at starting productive AI conversations.
        Given a topic or concept, generate:
        1. title: Concise conversation title (under 60 characters, engaging)
        2. initial_message: Opening message that frames the discussion (2-3 sentences, sets context and invites participation)

        Return ONLY a valid JSON object with these exact keys: "title", "initial_message".
        Do not include markdown formatting, code blocks, or any text outside the JSON.
      PROMPT
      output_format: :json
    }
  }.freeze

  def self.generate(profile:, context:, account:)
    new(profile: profile, context: context, account: account).generate
  end

  def initialize(profile:, context:, account:)
    @profile = profile.to_sym
    @context = context
    @account = account
    @profile_config = PROFILES[@profile]
  end

  def generate
    validate_profile!
    validate_context!

    model = find_suitable_model
    raise NoModelError, "No AI model available. Please configure a default model or enable a free model in AI Providers." unless model

    response = call_ai_api(model)
    parse_response(response)
  rescue NoModelError
    raise
  rescue LLM::APIError => e
    Rails.logger.error "[ContentGenerator] API error for #{@profile}: #{e.message}"
    raise GenerationError, "AI API error: #{e.message}"
  rescue NoModelError, UnknownProfileError
    raise
  rescue GenerationError
    raise
  rescue => e
    Rails.logger.error "[ContentGenerator] Error for #{@profile}: #{e.message}"
    raise GenerationError, "Failed to generate #{@profile}: #{e.message}"
  end

  private

  def validate_profile!
    raise UnknownProfileError, "Unknown profile: #{@profile}. Available: #{PROFILES.keys.join(', ')}" unless @profile_config
  end

  def validate_context!
    raise GenerationError, "Context cannot be blank" if @context.blank?
  end

  def find_suitable_model
    # Prefer account's default model, then fall back to free model
    @account.default_llm_model&.enabled? ? @account.default_llm_model : @account.llm_models.enabled.free.first
  end

  def call_ai_api(model)
    user_prompt = build_user_prompt

    model.api.chat(
      [ { role: "user", content: user_prompt } ],
      system_prompt: @profile_config[:system_prompt],
      temperature: 0.7,
      max_tokens: 2000
    )
  end

  def build_user_prompt
    case @profile
    when :advisor
      <<~PROMPT
        Create an AI advisor profile based on this concept:

        "#{@context}"

        Generate a name, short description, and comprehensive system prompt for this advisor.
      PROMPT
    when :council
      <<~PROMPT
        Create a compelling description for an AI advisor council named:

        "#{@context}"

        The description should explain what this council helps users accomplish.
      PROMPT
    when :conversation
      <<~PROMPT
        Create a conversation starter for a discussion about:

        "#{@context}"

        Generate an engaging title and opening message.
      PROMPT
    else
      @context.to_s
    end
  end

  def parse_response(response)
    content = response&.[](:content)
    raise GenerationError, "Empty response from AI" if content.blank?

    case @profile_config[:output_format]
    when :json
      parse_json_response(content)
    when :text
      parse_text_response(content)
    else
      { content: content.strip }
    end
  end

  def parse_json_response(content)
    # Clean up common AI response issues
    cleaned = content.strip

    # Remove markdown code blocks if present
    cleaned = cleaned.gsub(/```json\s*/, "").gsub(/```\s*$/, "").strip

    # Remove any text before the first { and after the last }
    if cleaned.include?("{") && cleaned.include?("}")
      start_idx = cleaned.index("{")
      end_idx = cleaned.rindex("}")
      cleaned = cleaned[start_idx..end_idx] if start_idx && end_idx
    end

    begin
      parsed = JSON.parse(cleaned)
    rescue JSON::ParserError => e
      Rails.logger.error "[ContentGenerator] JSON parse error: #{e.message}. Content: #{content.inspect}"
      raise GenerationError, "Failed to parse AI response as JSON"
    end

    # Validate all expected fields are present
    expected_fields = @profile_config[:fields].map(&:to_s)
    missing_fields = expected_fields - parsed.keys

    if missing_fields.any?
      raise GenerationError, "AI response missing fields: #{missing_fields.join(', ')}"
    end

    # Convert string keys to symbols and return only expected fields
    result = {}
    expected_fields.each do |field|
      value = parsed[field]
      result[field.to_sym] = value.to_s.strip if value
    end

    result
  end

  def parse_text_response(content)
    field = @profile_config[:fields].first
    { field => content.strip }
  end
end
