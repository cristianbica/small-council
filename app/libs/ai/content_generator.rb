# frozen_string_literal: true


module AI
  # High-level API for common content generation tasks
  #
  # This is a stateful (instance-based) class that provides intent-based methods
  # for generating content. Controllers and jobs call these methods rather than
  # building prompts directly.
  #
  # Features:
  # - Intent-based methods (e.g., generate_advisor_response, not chat)
  # - Automatic TokenUsage tracking (via Client)
  # - Caching layer (intent-based, not raw LLM call)
  # - Prompt templates using ERB
  # - No RubyLLM leakage - uses AI::Client internally
  #
  # Usage:
  #   generator = AI::ContentGenerator.new
  #   response = generator.generate_advisor_response(
  #     advisor: advisor,
  #     conversation: conversation,
  #     context: { memories: [...] }
  #   )
  #   message.update!(content: response.content)
  #
  class ContentGenerator
    class Error < StandardError; end
    class GenerationError < Error; end
    class NoModelError < Error; end

    DEFAULT_TEMPERATURE = 0.7
    CACHE_EXPIRY = 1.hour

    # Templates for different generation tasks
    TEMPLATES = {
      advisor_profile: <<~PROMPT,
        You are an expert at creating AI advisor profiles.
        Given a concept/role description, generate:
        1. name: Concise (2-4 words, professional, suitable as an identifier). Use Title Case.
        2. short_description: Brief (under 100 characters, for list views). One sentence.
        3. system_prompt: Comprehensive (2-4 paragraphs). Define personality, expertise, tone, response style, and boundaries.

        Return ONLY a valid JSON object with these exact keys: "name", "short_description", "system_prompt".
        Do not include markdown formatting, code blocks, or any text outside the JSON.

        Concept: <%= description %>
        <% if expertise.present? %>
        Expertise areas: <%= expertise.join(', ') %>
        <% end %>
      PROMPT

      council_description: <<~PROMPT,
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

        Council concept: <%= name %>
        Purpose: <%= purpose %>
      PROMPT

      conversation_summary: <<~PROMPT,
        Summarize the following conversation.
        <% if style == :brief %>
        Provide a brief summary (1-2 sentences) capturing the main points.
        <% elsif style == :detailed %>
        Provide a detailed summary (3-5 sentences) including key discussion points and conclusions.
        <% elsif style == :bullet_points %>
        Provide a summary in bullet points highlighting the main topics and decisions.
        <% end %>

        Conversation:
        <%= conversation_text %>
      PROMPT

      memory_content: <<~PROMPT
        Generate structured memory content based on the following information.
        Create a clear, well-organized record that captures the key information.

        <% if context[:format] == :json %>
        Return the content as a JSON object with appropriate structure.
        <% end %>

        Prompt: <%= prompt %>
        <% if context[:source] %>
        Source: <%= context[:source] %>
        <% end %>
      PROMPT
    }.freeze

    def initialize(client: nil, cache: Rails.cache)
      @client = client
      @cache = cache
    end

    # Generate an advisor response for a conversation
    #
    # @param advisor [Advisor] The advisor generating the response
    # @param conversation [Conversation] The conversation context
    # @param context [Hash] Additional context (memories, etc.)
    # @return [AI::Model::Response]
    def generate_advisor_response(advisor:, conversation:, context: {})
      cache_key = build_cache_key("advisor_response", advisor.id, conversation.id, context.hash)

      fetch_from_cache(cache_key) do
        client = build_client(advisor)
        builder = ContextBuilders::ConversationContextBuilder.new(
          conversation.council.space,
          conversation,
          context.slice(:memory_limit, :conversation_limit)
        )

        messages = build_conversation_messages(conversation)

        client.chat(
          messages: messages,
          context: builder.build.merge(context)
        )
      end
    end

    # Generate a summary of a conversation
    #
    # @param conversation [Conversation] The conversation to summarize
    # @param style [Symbol] Summary style: :brief, :detailed, :bullet_points
    # @return [String] The generated summary text
    def generate_conversation_summary(conversation:, style: :detailed)
      cache_key = build_cache_key("conversation_summary", conversation.id, style)

      fetch_from_cache(cache_key) do
        client = build_client_with_system_model(conversation.account)

        conversation_text = format_conversation_for_summary(conversation)
        prompt = render_template(:conversation_summary,
          conversation_text: conversation_text,
          style: style
        )

        response = client.complete(prompt: prompt)
        response.content.strip
      end
    end

    # Generate structured memory content
    #
    # @param prompt [String] The prompt describing what to generate
    # @param context [Hash] Additional context (source, format, etc.)
    # @return [String] The generated memory content
    def generate_memory_content(prompt:, context: {})
      cache_key = build_cache_key("memory_content", prompt.hash, context.hash)

      fetch_from_cache(cache_key) do
        # Use account from context or raise
        account = context[:account]
        raise GenerationError, "Account required in context" unless account

        client = build_client_with_system_model(account)

        rendered_prompt = render_template(:memory_content,
          prompt: prompt,
          context: context
        )

        response = client.complete(prompt: rendered_prompt)
        response.content.strip
      end
    end

    # Generate an advisor profile from a description
    #
    # @param description [String] Description of the advisor concept
    # @param expertise [Array<String>] Optional list of expertise areas
    # @param account [Account] The account for model selection
    # @return [Hash] Hash with :name, :short_description, :system_prompt
    def generate_advisor_profile(description:, expertise: [], account:)
      cache_key = build_cache_key("advisor_profile", description.hash, expertise.hash)

      fetch_from_cache(cache_key) do
        client = build_client_with_system_model(account)

        prompt = render_template(:advisor_profile,
          description: description,
          expertise: expertise
        )

        response = client.complete(prompt: prompt)
        parse_json_response(response.content)
      end
    end

    # Generate a council description from a name and purpose
    #
    # @param name [String] The council name/concept
    # @param purpose [String] The council's purpose
    # @param account [Account] The account for model selection
    # @return [Hash] Hash with :name, :description
    def generate_council_description(name:, purpose:, account:)
      cache_key = build_cache_key("council_description", name.hash, purpose.hash)

      fetch_from_cache(cache_key) do
        client = build_client_with_system_model(account)

        prompt = render_template(:council_description,
          name: name,
          purpose: purpose
        )

        response = client.complete(prompt: prompt)
        parse_json_response(response.content)
      end
    end

    private

    def build_client(advisor)
      return @client if @client

      model = advisor.effective_llm_model
      raise NoModelError, "No AI model available for advisor" unless model

      Client.new(
        model: model,
        system_prompt: advisor.system_prompt,
        temperature: DEFAULT_TEMPERATURE
      )
    end

    def build_client_with_system_model(account)
      return @client if @client

      model = find_suitable_model(account)
      raise NoModelError, "No AI model available. Please configure a default model or enable at least one model." unless model

      Client.new(
        model: model,
        temperature: DEFAULT_TEMPERATURE
      )
    end

    def find_suitable_model(account)
      # Prefer account's default model, then fall back to free model
      account.default_llm_model&.enabled? ? account.default_llm_model : account.llm_models.enabled.free.first
    end

    def build_conversation_messages(conversation)
      # Get messages from conversation
      conversation.messages.chronological.map do |msg|
        {
          role: msg.role == "advisor" ? "assistant" : msg.role,
          content: msg.content
        }
      end
    end

    def format_conversation_for_summary(conversation)
      conversation.messages.chronological.map do |msg|
        sender_name = msg.sender.respond_to?(:name) ? msg.sender.name : msg.sender.to_s
        "#{sender_name}: #{msg.content}"
      end.join("\n\n")
    end

    def render_template(template_name, locals)
      template = TEMPLATES[template_name]
      raise GenerationError, "Unknown template: #{template_name}" unless template

      ERB.new(template, trim_mode: "-").result_with_hash(locals)
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

      JSON.parse(cleaned, symbolize_names: true)
    rescue JSON::ParserError => e
      Rails.logger.error "[AI::ContentGenerator] JSON parse error: #{e.message}. Content: #{content.inspect}"
      raise GenerationError, "Failed to parse AI response as JSON"
    end

    def fetch_from_cache(key)
      return yield unless @cache

      @cache.fetch(key, expires_in: CACHE_EXPIRY) do
        yield
      end
    end

    def build_cache_key(prefix, *components)
      parts = components.map { |c| c.to_s.hash.to_s(16) }
      "ai/content_generator/#{prefix}/#{parts.join('/')}"
    end
  end
end
