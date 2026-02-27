# Parallel AI Implementation Plan

**Date:** 2026-02-27
**Status:** APPROVED – Ready for implementation
**Scope:** Reimplement current AI functionality in `app/ai/` with cleaner DSL
**Strategy:** Build parallel, then migrate
**Goal:** Same functionality, better organization, clearer DSL, testable

---

## Scope Clarification

**This is a REIMPLEMENTATION, not new features.**

We will rebuild what exists now:
- Same tool capabilities (ask advisor, query memories, etc.)
- Same ContentGenerator functionality
- Same conversation flow
- Same AI model responses

**What changes:**
- Cleaner code organization
- Better separation of concerns
- No RubyLLM leakage to controllers
- Flatter tool hierarchy
- Easier to test

**What does NOT change:**
- User-facing behavior
- Database schema
- Business logic outcomes
- Feature set

---

## Philosophy

**Current problems:**
- Controllers know about `RubyLLM.context`, `RubyLLM::Tool`, provider configs
- Tool classes scattered across 3 hierarchies (20+ files)
- `AIClient` is 480-line god class
- Testing requires full RubyLLM stack

**New philosophy:**
- Controllers say: "I need content generated for this purpose"
- AI layer says: "I'll figure out which model, tools, and prompt"
- Tools are business-domain organized (conversations/, internal/, external/)
- Easy to test: mock `AI::Client` responses

---

## Architecture Overview

```
app/ai/
├── client.rb                    # Entry point - wraps RubyLLM
├── model.rb                     # Value object - normalized response
├── content_generator.rb         # High-level API for controllers (stateful, like current)
├── concerns/
│   └── client/                  # Split if client gets complex
│       ├── provider_config.rb   # OpenAI, OpenRouter config
│       ├── error_handler.rb     # Retry logic, error normalization
│       └── token_tracker.rb     # Usage tracking, cost calculation (AUTO)
└── tools/
    ├── base_tool.rb             # All tools inherit from this
    ├── conversations/           # Tools related to current conversation flow
    │   ├── ask_advisor_tool.rb              # Ask another advisor a question
    │   ├── summarize_conversation_tool.rb   # Get conversation summary
    │   └── finish_conversation_tool.rb      # Mark conversation finished
    ├── internal/                # Data access tools (CRUD operations)
    │   ├── create_memory_tool.rb           # Create a memory record
    │   ├── list_memories_tool.rb           # List memories with metadata
    │   ├── query_memories_tool.rb          # Search memories
    │   ├── read_memory_tool.rb             # Read full memory content
    │   ├── update_memory_tool.rb           # Update memory content
    │   ├── list_conversations_tool.rb      # List conversations
    │   ├── query_conversations_tool.rb     # Search conversations
    │   ├── read_conversation_tool.rb       # Read conversation content
    │   └── get_conversation_summary_tool.rb # Get stored summary
    └── external/                # External API tools
        └── browse_web_tool.rb   # Browse external websites
```

**Key Decision: Domain-Organized with Clear Naming**
- Tools organized by domain: `conversations/`, `internal/`, `external/`
- Clear naming: `create_memory_tool.rb` not `create_tool.rb`
- Full class names: `AI::Tools::CreateMemoryTool` (module inferred from directory)

---

## Component Specifications

### 1. AI::Client

**Purpose:** Wrap RubyLLM, provide clean interface, hide implementation details

**File:** `app/ai/client.rb`

**Interface:**
```ruby
module AI
  class Client
    def initialize(model:, tools: [], system_prompt: nil, temperature: 0.7)
      # model: LlmModel instance
      # tools: Array of AI::Tools::BaseTool instances (stateless)
      @model = model
      @tools = tools
      @system_prompt = system_prompt
      @temperature = temperature
    end

    # Context passed at generation time, not initialization
    def chat(messages: [], context: {}, &block)
      # messages: Array of { role: "user|assistant|system", content: String }
      # context: Hash with :space, :conversation, :user, :advisor, etc.
      # block: Optional streaming handler
      # Returns: AI::Model::Response
    end

    def complete(prompt:, context: {})
      # Single-turn completion
      # context: Execution context for tools
      # Returns: AI::Model::Response
    end

    private

    def build_ruby_llm_chat(context)
      # Internal: Configure RubyLLM with provider settings
      # Set context on tool adapters so they can pass to tools
    end

    def normalize_response(ruby_llm_response)
      # Internal: Convert to AI::Model::Response
    end
  end
end
```

**Usage Example:**
```ruby
# Controller or service code
client = AI::Client.new(
  model: advisor.llm_model,
  tools: [
    AI::Tools::Internal::QueryMemoriesTool.new,     # No context here!
    AI::Tools::Internal::CreateMemoryTool.new
  ],
  system_prompt: advisor.system_prompt
)

# Context passed at generation time
response = client.chat(
  messages: conversation.messages_for_llm,
  context: {                                         # Context here!
    space: conversation.space,
    conversation: conversation,
    user: conversation.user,
    advisor: advisor
  }
)
# => AI::Model::Response
# Note: TokenUsage is automatically created
```

**Key Design Decisions:**
- Takes `LlmModel` instance, not string identifier
- Takes tool **instances** (stateless, no context), not classes
- Context passed at `chat()` time, not tool initialization
- Returns normalized `AI::Model::Response`, not RubyLLM response
- No RubyLLM types leak through interface

---

### 2. AI::Model

**Purpose:** Value objects for AI interactions - normalized across providers

**File:** `app/ai/model.rb` (or `app/ai/model/*.rb` if multiple)

**Classes:**
```ruby
module AI
  module Model
    class Response
      attr_reader :content, :tool_calls, :usage, :raw

      def initialize(content:, tool_calls: [], usage: {}, raw: nil)
        @content = content      # String - the text response
        @tool_calls = tool_calls # Array of ToolCall
        @usage = usage          # TokenUsage
        @raw = raw              # Original provider response (for debugging)
      end

      def tool_call?
        tool_calls.any?
      end
    end

    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments: {})
        @id = id
        @name = name
        @arguments = arguments  # Hash of params
      end
    end

    class TokenUsage
      attr_reader :input_tokens, :output_tokens, :total_tokens

      def initialize(input:, output:)
        @input_tokens = input
        @output_tokens = output
        @total_tokens = input + output
      end

      def estimated_cost(model)
        # Calculate based on model pricing
      end
    end

    class Message
      attr_reader :role, :content, :tool_calls

      ROLES = %w[system user assistant tool].freeze

      def initialize(role:, content:, tool_calls: nil)
        raise ArgumentError, "Invalid role: #{role}" unless ROLES.include?(role)
        @role = role
        @content = content
        @tool_calls = tool_calls
      end

      def to_h
        { role: role, content: content }
      end
    end
  end
end
```

**Why separate Model classes?**
- RubyLLM returns different structures for OpenAI vs OpenRouter
- We normalize to common interface
- Easy to serialize for caching/logging
- Can add helper methods (cost calculation, etc.)

---

### 3. AI::ContentGenerator

**Purpose:** High-level API for common content generation tasks (stateful, like current implementation)

**File:** `app/ai/content_generator.rb`

**Design Decision:** Stateful (instance-based), same pattern as current ContentGenerator

**Interface:**
```ruby
module AI
  class ContentGenerator
    def initialize(client: nil)
      @client = client || default_client
    end

    # High-level methods for specific use cases
    def generate_advisor_response(advisor:, conversation:, context: {})
      # Build prompt, call client, return response
    end

    def generate_conversation_summary(conversation:, style: :detailed)
      # Summarize conversation history
    end

    def generate_memory_content(prompt:, context: {})
      # Generate structured memory content
    end

    def generate_advisor_profile(description:, expertise:)
      # Generate advisor system prompt from description
    end

    def generate_council_description(name:, purpose:)
      # Generate council description
    end

    private

    def default_client
      # Create default client with system model
    end

    def build_prompt(template, locals)
      # Use ERB or similar for prompt templates
    end
  end
end
```

**Usage Example:**
```ruby
# In controller or job
generator = AI::ContentGenerator.new

response = generator.generate_advisor_response(
  advisor: advisor,
  conversation: conversation,
  context: { memories: recent_memories }
)

# Process response
message.update!(content: response.content)
```

**Why this layer?**
- Controllers don't build prompts - they call intent-based methods
- Easy to test: mock ContentGenerator, not whole LLM stack
- Can add caching, rate limiting here
- Prompt templates live in one place

---

### 4. AI::Tools::BaseTool

**Purpose:** Base class for all tools - unified interface

**File:** `app/ai/tools/base_tool.rb`

**Interface:**
```ruby
module AI
  module Tools
    class BaseTool
      # Tool metadata - used by LLM
      def name
        self.class.name.demodulize.underscore.gsub('_tool', '')
      end

      def description
        raise NotImplementedError
      end

      def parameters
        # Return JSON Schema-like structure
        # {
        #   type: "object",
        #   properties: {
        #     query: { type: "string", description: "..." }
        #   },
        #   required: [:query]
        # }
        raise NotImplementedError
      end

      # Execution - called when LLM invokes tool
      # Context is passed at execution time, not initialization
      def execute(arguments = {}, context = {})
        raise NotImplementedError
      end

      # Tool result format
      def format_result(data)
        # Return string or hash that LLM can understand
        data.to_json
      end

      # Convert to RubyLLM tool format (internal use)
      def to_ruby_llm_tool
        AI::Adapters::RubyLLMToolAdapter.new(self)
      end

      protected

      def validate_context!(context, *required_keys)
        missing = required_keys - context.keys
        raise ArgumentError, "Missing context: #{missing.join(', ')}" if missing.any?
      end
    end
  end
end
```

**Key Design Decisions:**
- Tools are **stateless** - no context at initialization
- Context passed to `execute(arguments, context)` at call time
- Same tool instance can be reused across different contexts
- `parameters` method defines JSON Schema for LLM
- `to_ruby_llm_tool` adapts for RubyLLM (hidden from callers)

---

### 5. Conversation Tools

**Directory:** `app/ai/tools/conversations/`

**Purpose:** Tools that manage conversation flow between advisors

#### 5.1 AskAdvisorTool

**File:** `app/ai/tools/conversations/ask_advisor_tool.rb`

```ruby
module AI
  module Tools
    module Conversations
      class AskAdvisorTool < BaseTool
        def description
          "Ask a specific advisor a question. Use this to get input from other advisors."
        end

        def parameters
          {
            type: "object",
            properties: {
              advisor_name: {
                type: "string",
                description: "Name of the advisor to ask"
              },
              question: {
                type: "string",
                description: "The question to ask"
              }
            },
            required: [:advisor_name, :question]
          }
        end

        # Context passed at execution time
        def execute(arguments = {}, context = {})
          validate_context!(context, :space, :conversation)

          advisor = find_advisor(context[:space], arguments[:advisor_name])
          return { error: "Advisor not found" } unless advisor

          message = create_mention_message(context, advisor, arguments[:question])
          enqueue_response_job(advisor, message, context[:conversation])

          { success: true, message: "Asked #{advisor.name}", message_id: message.id }
        end

        private

        def find_advisor(space, name)
          space.advisors.find { |a| a.name.downcase.include?(name.downcase) }
        end

        def create_mention_message(context, advisor, question)
          context[:conversation].messages.create!(
            sender: context[:user] || context[:advisor],
            role: "user",
            content: "@#{advisor.name} #{question}"
          )
        end

        def enqueue_response_job(advisor, message, conversation)
          GenerateAdvisorResponseJob.perform_later(
            advisor_id: advisor.id,
            conversation_id: conversation.id
          )
        end
      end
    end
  end
end
```

#### 5.2 SummarizeConversationTool

**File:** `app/ai/tools/conversations/summarize_conversation_tool.rb`

```ruby
module AI
  module Tools
    module Conversations
      class SummarizeConversationTool < BaseTool
        def description
          "Get a summary of the conversation so far. Useful to understand context."
        end

        def parameters
          {
            type: "object",
            properties: {
              style: {
                type: "string",
                enum: ["brief", "detailed", "bullet_points"],
                description: "Style of summary"
              }
            },
            required: [:style]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :conversation)
          style = arguments[:style] || "brief"

          conversation = context[:conversation]

          # Get recent messages (not the whole history)
          messages = conversation.messages.recent.limit(50)

          summary = generate_summary(messages, style)

          { summary: summary, message_count: messages.count }
        end

        private

        def generate_summary(messages, style)
          # Call ContentGenerator to create summary
          generator = AI::ContentGenerator.new
          generator.generate_conversation_summary(
            conversation: messages,
            style: style
          )
        end
      end
    end
  end
end
```

#### 5.3 FinishConversationTool

**File:** `app/ai/tools/conversations/finish_conversation_tool.rb`

```ruby
module AI
  module Tools
    module Conversations
      class FinishConversationTool < BaseTool
        def description
          "Mark this conversation as finished. Triggers final summary and memory creation."
        end

        def parameters
          {
            type: "object",
            properties: {
              reason: {
                type: "string",
                description: "Why the conversation is being finished"
              }
            },
            required: [:reason]
          }
        end

        def execute(reason:)
          conversation = context[:conversation]

          # Trigger conversation lifecycle
          lifecycle = ConversationLifecycle.new(conversation)
          lifecycle.begin_conclusion_process(reason: reason)

          {
            success: true,
            message: "Conversation marked as finishing. Summary will be generated.",
            conversation_id: conversation.id
          }
        end
      end
    end
  end
end
```

---

### 6. Internal Tools

**Directory:** `app/ai/tools/internal/`

**Purpose:** CRUD operations on internal data (memories, conversations)

#### 6.1 Memory Tools

**File:** `app/ai/tools/internal/create_memory_tool.rb`

```ruby
module AI
  module Tools
    module Internal
      class CreateMemoryTool < BaseTool
        def description
          "Create a new memory record with a title and content."
        end

        def parameters
          {
            type: "object",
            properties: {
              title: { type: "string", description: "Title of the memory" },
              content: { type: "string", description: "Content of the memory" },
              tags: {
                type: "array",
                items: { type: "string" },
                description: "Optional tags"
              }
            },
            required: [:title, :content]
          }
        end

        # Context passed at execution time
        def execute(arguments = {}, context = {})
          validate_context!(context, :space)

          memory = context[:space].memories.create!(
            title: arguments[:title],
            content: arguments[:content],
            tags: arguments[:tags] || [],
            created_by: context[:advisor] || context[:user]
          )

          { success: true, memory_id: memory.id, title: memory.title }
        end
      end
    end
  end
end
```

Similar pattern for:
- `list_memories_tool.rb` - List memories with pagination
- `query_memories_tool.rb` - Search memories
- `read_memory_tool.rb` - Get full memory content
- `update_memory_tool.rb` - Update existing memory

#### 6.2 Conversation Tools

Similar structure for conversation CRUD:
- `list_conversations_tool.rb` - List past conversations
- `query_conversations_tool.rb` - Search conversations
- `read_conversation_tool.rb` - Read conversation messages
- `get_conversation_summary_tool.rb` - Get stored summary

---

### 7. External Tools

**Directory:** `app/ai/tools/external/`

#### 7.1 BrowseWebTool

**File:** `app/ai/tools/external/browse_web_tool.rb`

```ruby
module AI
  module Tools
    module External
      class BrowseWebTool < BaseTool
        def description
          "Browse the web for recent information. Use for current events or fact-checking."
        end

        def parameters
          {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "URL to browse"
              },
              extract_text: {
                type: "boolean",
                description: "Extract main text content (default: true)"
              }
            },
            required: [:url]
          }
        end

        def execute(url:, extract_text: true)
          # Use existing WebBrowserService or implement here
          browser = WebBrowserService.new
          result = browser.fetch(url, extract_content: extract_text)

          {
            url: url,
            title: result[:title],
            content: result[:content]&.truncate(5000),
            success: result[:success]
          }
        end
      end
    end
  end
end
```

---

## Client Concerns (Split if needed)

**Directory:** `app/ai/concerns/client/`

If `AI::Client` grows beyond 200 lines, split into concerns:

```ruby
# app/ai/concerns/client/provider_config.rb
module AI
  module Concerns
    module Client
      module ProviderConfig
        def configure_ruby_llm(config)
          case provider_type
          when "openai"
            config.openai_api_key = api_key
            config.openai_organization_id = organization_id
          when "openrouter"
            config.openrouter_api_key = api_key
          end
        end
      end
    end
  end
end

# app/ai/concerns/client/error_handler.rb
module AI
  module Concerns
    module Client
      module ErrorHandler
        def with_retry(max_attempts: 3)
          attempts = 0
          begin
            yield
          rescue RubyLLM::RateLimitError => e
            attempts += 1
            sleep(2 ** attempts)  # Exponential backoff
            retry if attempts < max_attempts
            raise
          rescue RubyLLM::Error => e
            # Log and re-raise
            Rails.logger.error "[AI::Client] Error: #{e.message}"
            raise
          end
        end
      end
    end
  end
end

# app/ai/concerns/client/token_tracker.rb
module AI
  module Concerns
    module Client
      module TokenTracker
        def track_usage(response)
          TokenUsage.create!(
            model: model.identifier,
            input_tokens: response.usage.input_tokens,
            output_tokens: response.usage.output_tokens,
            conversation: context[:conversation]
          )
        end
      end
    end
  end
end
```

---

## Adapter Layer (Hidden from Callers)

**Directory:** `app/ai/adapters/`

Adapters convert our clean interface to RubyLLM's interface. Callers never see these.

```ruby
# app/ai/adapters/ruby_llm_tool_adapter.rb
module AI
  module Adapters
    class RubyLLMToolAdapter < RubyLLM::Tool
      # Context is stored at adapter level (passed from Client during chat)
      attr_accessor :context

      def initialize(ai_tool)
        @ai_tool = ai_tool
        @context = {}  # Set by Client before execution

        # Define parameters dynamically from tool schema
        schema = @ai_tool.parameters
        schema[:properties].each do |name, config|
          param name,
                type: config[:type]&.to_sym || :string,
                desc: config[:description] || "",
                required: schema[:required]&.include?(name.to_s) || false
        end
      end

      def execute(**args)
        # Pass context at execution time
        result = @ai_tool.execute(args, context)
        result.to_json
      rescue => e
        Rails.logger.error "[RubyLLMToolAdapter] #{@ai_tool.name} failed: #{e.message}"
        { error: e.message }
      end
    end
  end
end
```

---

## Usage Examples

### Example 1: Scribe Chat (Current vs New)

**Current (in controller):**
```ruby
# 65+ lines of RubyLLM configuration
ruby_context = RubyLLM.context { |c| ... }
chat = ruby_context.chat(model: ...).with_tools(
  RubyLLMTools::CreateMemoryTool,
  RubyLLMTools::QueryMemoriesTool
)
chat.add_message(...)
response = chat.complete
```

**New (in controller):**
```ruby
# Create client once (tools are stateless)
client = AI::Client.new(
  model: scribe_model,
  tools: [
    AI::Tools::Internal::QueryMemoriesTool.new,   # No context!
    AI::Tools::Internal::CreateMemoryTool.new,
    AI::Tools::External::BrowseWebTool.new
  ],
  system_prompt: prompt
)

# Pass context at generation time
response = client.chat(
  messages: messages,
  context: {
    space: @space,
    conversation: @conversation,
    user: Current.user,
    advisor: @advisor
  }
)
# response => AI::Model::Response
# TokenUsage automatically created
```

### Example 2: Advisor Response (Current vs New)

**Current:**
```ruby
# In GenerateAdvisorResponseJob
client = AIClient.new(advisor: advisor, conversation: conversation)
client.generate_response
# TokenUsage created inside, somewhere
```

**New:**
```ruby
# In GenerateAdvisorResponseJob
# Create client (stateless tools)
client = AI::Client.new(
  model: advisor.effective_llm_model,
  tools: [
    AI::Tools::Internal::QueryMemoriesTool.new,
    AI::Tools::Conversations::AskAdvisorTool.new
  ],
  system_prompt: advisor.system_prompt
)

# Pass context at generation time
response = client.chat(
  messages: conversation.messages_for_llm,
  context: {
    space: conversation.space,
    conversation: conversation,
    user: conversation.user,
    advisor: advisor,
    memories: recent_memories
  }
)

message.update!(content: response.content)
# TokenUsage automatically created and saved
```

### Example 3: Testing (Current vs New)

**Current (hard to test):**
```ruby
# Requires mocking RubyLLM, Thread.current, etc.
```

**New (easy to test):**
```ruby
# Test without RubyLLM
client = double("AI::Client")
allow(client).to receive(:chat).and_return(
  AI::Model::Response.new(content: "Test response")
)

allow(AI::Client).to receive(:new).and_return(client)

# Test controller logic
post :chat, params: { message: "Hello" }
expect(response).to be_successful
```

---

### 8. Context Builders

**Purpose:** Encapsulate different context building strategies

**Directory:** `app/ai/context_builders/`

**Current Problem:** `AIClient` has messy methods like `build_memory_context`, `build_council_context` mixed with API logic (480 lines)

**Solution:** Separate context building from AI client

```ruby
# app/ai/context_builders/base_context_builder.rb
module AI
  module ContextBuilders
    class BaseContextBuilder
      def initialize(space, conversation = nil, options = {})
        @space = space
        @conversation = conversation
        @options = options
      end

      def build
        raise NotImplementedError
      end

      protected

      def recent_memories(limit: 10)
        @space.memories.active.recent.limit(limit)
      end

      def recent_conversations(limit: 5)
        return [] unless @conversation
        @space.conversations.where.not(id: @conversation.id).recent.limit(limit)
      end
    end
  end
end

# app/ai/context_builders/conversation_context_builder.rb
module AI
  module ContextBuilders
    class ConversationContextBuilder < BaseContextBuilder
      # For: Advisors responding in conversations
      # Includes: Space memories + Current conversation context

      def build
        {
          space: @space,
          conversation: @conversation,
          user: @conversation.user,
          memories: recent_memories(limit: @options[:memory_limit] || 10),
          related_conversations: recent_conversations(limit: 3),
          council: @conversation.council
        }
      end
    end
  end
end

# app/ai/context_builders/scribe_context_builder.rb
module AI
  module ContextBuilders
    class ScribeContextBuilder < BaseContextBuilder
      # For: Scribe chat mode
      # Includes: Space memories only (no specific conversation)

      def build
        {
          space: @space,
          user: @options[:user],
          advisor: @options[:advisor],  # Scribe advisor
          memories: recent_memories(limit: @options[:memory_limit] || 20),
          recent_conversations: @space.conversations.recent.limit(5)
        }
      end
    end
  end
end
```

**Usage:**

```ruby
# In GenerateAdvisorResponseJob
builder = AI::ContextBuilders::ConversationContextBuilder.new(
  conversation.space,
  conversation,
  memory_limit: 10
)

client = AI::Client.new(model: model, tools: tools, system_prompt: prompt)
response = client.chat(
  messages: messages,
  context: builder.build
)

# In SpaceScribeController
builder = AI::ContextBuilders::ScribeContextBuilder.new(
  @space,
  nil,
  user: Current.user,
  advisor: @advisor,
  memory_limit: 20
)

client.chat(
  messages: messages,
  context: builder.build
)
```

**Benefits:**
- Encapsulates 2 different context strategies you mentioned
- Testable in isolation
- Reusable between old and new AI systems during migration
- No more 480-line god class

---

## Implementation Phases

### Phase 1: Build Core (Days 1-5)
**Goal:** Create foundation without touching existing code

- [ ] Create `app/ai/` directory structure
- [ ] Implement `AI::Client` (wraps RubyLLM)
- [ ] Implement `AI::Model::Response`, `AI::Model::ToolCall`, `AI::Model::TokenUsage`
- [ ] Implement `AI::Tools::BaseTool`
- [ ] Implement `AI::Tools::QueryMemoriesTool` (one complete tool as proof of concept)
- [ ] **Write tests:**
  - Unit tests for `AI::Client` (mock RubyLLM)
  - Unit tests for `AI::Model` value objects
  - Unit test for `BaseTool` (ensure interface contract)
  - Integration test: `AI::Client` → `RubyLLMToolAdapter` → `QueryMemoriesTool` with mocked context
  - One controller-level test showing how to mock `AI::Client` in existing controllers

**Deliverable:** Core infrastructure tested and working

### Phase 2: Build All Tools (Days 6-10)
**Goal:** Implement all tool functionality

**Conversations tools:**
- [ ] `AI::Tools::Conversations::AskAdvisorTool`
- [ ] `AI::Tools::Conversations::SummarizeConversationTool`
- [ ] `AI::Tools::Conversations::FinishConversationTool`

**Internal tools:**
- [ ] `AI::Tools::Internal::CreateMemoryTool`
- [ ] `AI::Tools::Internal::ListMemoriesTool`
- [ ] `AI::Tools::Internal::QueryMemoriesTool`
- [ ] `AI::Tools::Internal::ReadMemoryTool`
- [ ] `AI::Tools::Internal::UpdateMemoryTool`
- [ ] `AI::Tools::Internal::ListConversationsTool`
- [ ] `AI::Tools::Internal::QueryConversationsTool`
- [ ] `AI::Tools::Internal::ReadConversationTool`
- [ ] `AI::Tools::Internal::GetConversationSummaryTool`

**External tools:**
- [ ] `AI::Tools::External::BrowseWebTool`

**Adapter:**
- [ ] `AI::Adapters::RubyLLMToolAdapter`

**Deliverable:** All tools implemented with tests

### Phase 3: ContentGenerator (Days 11-13)
**Goal:** High-level API matching current functionality

- [ ] `AI::ContentGenerator` class (stateful)
- [ ] `#generate_advisor_response`
- [ ] `#generate_conversation_summary`
- [ ] `#generate_memory_content`
- [ ] `#generate_advisor_profile`
- [ ] `#generate_council_description`
- [ ] Automatic TokenUsage tracking
- [ ] Caching layer

**Deliverable:** ContentGenerator ready to replace current one

### Phase 4: One-by-One Migration (Days 14-25)
**Goal:** Migrate each AI usage point individually with feature flags

**Current AI Usage Inventory:**

| # | Location | Current Class | New Class | Complexity |
|---|----------|---------------|-----------|------------|
| 1 | `AdvisorsController#generate_profile` | `ContentGenerator` | `AI::ContentGenerator#generate_advisor_profile` | Low |
| 2 | `CouncilsController#generate_description` | `ContentGenerator` | `AI::ContentGenerator#generate_council_description` | Low |
| 3 | `GenerateConversationSummaryJob` | `AIClient` | `AI::ContentGenerator#generate_conversation_summary` | Medium |
| 4 | `GenerateAdvisorResponseJob` | `AIClient` | `AI::ContentGenerator#generate_advisor_response` | High |
| 5 | `SpaceScribeController#chat` | RubyLLM direct | `AI::Client` + tools | High |

**Migration Order (easiest first):**

#### 4.1 Content Generation - Advisor Profiles (Day 14)
**Files:** `app/controllers/advisors_controller.rb`
- [ ] Create `Features` flag system (if not exists)
- [ ] Add `use_new_ai_advisor_profiles` flag
- [ ] Implement dual-path in `AdvisorsController#generate_profile`
- [ ] Log both outputs for comparison
- [ ] Test with real advisor creation flows
- [ ] Fix discrepancies

**Success Criteria:** New AI produces equivalent advisor profiles

#### 4.2 Content Generation - Council Descriptions (Day 15)
**Files:** `app/controllers/councils_controller.rb`
- [ ] Add `use_new_ai_council_descriptions` flag
- [ ] Implement dual-path in `CouncilsController#generate_description`
- [ ] Log both outputs for comparison
- [ ] Test council creation flows
- [ ] Fix discrepancies

**Success Criteria:** New AI produces equivalent council descriptions

#### 4.3 Conversation Summary Job (Days 16-17)
**Files:** `app/jobs/generate_conversation_summary_job.rb`
- [ ] Add `use_new_ai_summaries` flag
- [ ] Refactor job to support both `AIClient` and `AI::ContentGenerator`
- [ ] Add output comparison logging
- [ ] Run parallel processing (old for production, new for comparison)
- [ ] Validate summary quality matches
- [ ] Fix discrepancies

**Success Criteria:** Conversation summaries are equivalent

#### 4.4 Advisor Response Job (Days 18-20)
**Files:** `app/jobs/generate_advisor_response_job.rb`
- [ ] Add `use_new_ai_advisor_responses` flag
- [ ] Create adapter to bridge job to new `AI::ContentGenerator`
- [ ] Implement side-by-side response generation
- [ ] Log and compare responses (don't show new to users yet)
- [ ] Validate tool calling behavior matches
- [ ] Fix discrepancies

**Success Criteria:** Advisor responses are equivalent, tools work correctly

#### 4.5 Space Scribe Chat (Days 21-25)
**Files:** `app/controllers/space_scribe_controller.rb`
- [ ] Add `use_new_ai_scribe` flag
- [ ] Implement new chat path using `AI::Client` + `AI::Tools`
- [ ] Migrate tool calls from `RubyLLMTools::*` to `AI::Tools::*`
- [ ] Run extensive testing (this is the main user-facing AI)
- [ ] Compare tool execution results
- [ ] Fix discrepancies

**Success Criteria:** Scribe chat works identically with new system

**Deliverable:** All AI usage points migrated with feature flags, new system proven equivalent

### Phase 5: Feature Flag Flip (Days 26-30)
**Goal:** Gradually switch to new system

**Week 1: Internal/Admin Features (Days 26-27)**
- [ ] Enable `use_new_ai_advisor_profiles` in production
- [ ] Enable `use_new_ai_council_descriptions` in production
- [ ] Monitor error rates and response quality
- [ ] Quick rollback if issues

**Week 2: Background Jobs (Days 28-29)**
- [ ] Enable `use_new_ai_summaries` in production
- [ ] Enable `use_new_ai_advisor_responses` in production
- [ ] Monitor job success rates
- [ ] Compare token usage (should be similar or better)

**Week 3: User-Facing Feature (Day 30)**
- [ ] Enable `use_new_ai_scribe` for 10% of users
- [ ] Monitor for 24 hours
- [ ] Increase to 50% if stable
- [ ] Full rollout if no issues

**Deliverable:** New system active for all users, old system unused

### Phase 6: Cleanup (Days 31-35)
**Goal:** Remove old code and reorganize

**Code Cleanup:**
- [ ] Delete `app/services/ai_client.rb`
- [ ] Delete `app/services/content_generator.rb` (old)
- [ ] Delete `app/services/scribe_tools/` directory
- [ ] Delete `app/services/advisor_tools/` directory
- [ ] Delete `app/services/ruby_llm_tools/` directory
- [ ] Remove all feature flags (keep flag infrastructure for future use)

**Test Reorganization** (follow Rails conventions):
> Note: Tests should mirror `app/` structure. Since AI code is in `app/libs/ai/`, tests should be in `test/libs/ai/`. Integration tests go in `test/integration/ai/`.

- [ ] Move `test/ai/unit/*` → `test/libs/ai/**/*`
- [ ] Move `test/ai/integration/*` → `test/integration/ai/**/*`
- [ ] Remove `test/ai/` directory
- [ ] Update test require paths

**Documentation:**
- [ ] Update `.ai/docs/features/ai-integration.md`
- [ ] Document new architecture for developers
- [ ] Update API docs if needed

**Deliverable:** Clean codebase with only new AI system, properly organized

---

## Total Timeline: 25 Days (5 Weeks)

---

## Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| **1. Context injection** | **Pass at execution time** | Tools are stateless, context passed to `chat(context: {})` |
| **2. Tool granularity** | **Domain-organized directories with clear file names** | `internal/create_memory_tool.rb` not `create_tool.rb` |
| **3. ContentGenerator** | **Stateful (instance)** | Match current pattern, allows dependency injection |
| **4. Streaming** | **Block parameter to `chat()`** | Simplest implementation, Ruby-idiomatic |
| **5. Error handling** | **Let exceptions bubble** | Controllers/jobs decide how to handle; consistent with Rails |
| **6. Caching** | **ContentGenerator level** | Intent-based caching, easy to invalidate |
| **7. Cost tracking** | **Automatic** | Always track usage, record TokenUsage on every call |

---

## Design Details

### Context Injection Design

**Selected: Context at Execution Time**

```ruby
# Tools are stateless - initialized without context
query_tool = AI::Tools::Internal::QueryMemoriesTool.new
create_tool = AI::Tools::Internal::CreateMemoryTool.new

# Client configured with stateless tools
client = AI::Client.new(
  model: advisor.llm_model,
  tools: [query_tool, create_tool],
  system_prompt: advisor.system_prompt
)

# Context passed at generation time
response = client.chat(
  messages: messages,
  context: {
    space: conversation.space,
    conversation: conversation,
    user: conversation.user,
    advisor: advisor
  }
)
```

**How it works:**
1. Tools are created once (stateless, no context)
2. Client is configured with tools
3. When `chat()` is called, context is passed
4. Client passes context to tool adapters
5. Adapters pass context to tool's `execute(args, context)` method

**Pros:**
- Tools are stateless and reusable
- Same tool instances can be used across different contexts
- Easy to test - no setup needed for tools
- Clear separation: config vs execution
- Thread-safe - no shared state in tools

**Cons:**
- Need to pass context on every call
- Context must flow through adapter layer

**Why not context at initialization?**
- Would need to create new tool instances for each request
- Tools couldn't be reused
- More memory allocation
- Harder to test (need to mock context)

**Why not Current scope?**
- Hidden dependencies
- Hard to test
- Thread safety issues
- Couples tools to request lifecycle

---

### Streaming Implementation

```ruby
# Simple block-based streaming
def chat(messages: [], &block)
  if block_given?
    # Streaming mode
    @ruby_llm_chat.complete(streaming: true) do |chunk|
      block.call(chunk.content)
    end
  else
    # Non-streaming mode
    response = @ruby_llm_chat.complete
    normalize_response(response)
  end
end

# Usage in controller
def chat
  client = AI::Client.new(...)

  client.chat(messages: messages) do |chunk|
    Turbo::StreamsChannel.broadcast_append_to(..., chunk)
  end
end
```

---

### Error Handling Strategy

**Let exceptions bubble up:**

```ruby
module AI
  class Client
    def chat(...)
      with_retry do
        response = @ruby_llm_chat.complete
        track_usage(response)  # Auto track
        normalize_response(response)
      end
    rescue RubyLLM::RateLimitError => e
      Rails.logger.error "[AI::Client] Rate limited: #{e.message}"
      raise  # Let caller handle
    rescue RubyLLM::Error => e
      Rails.logger.error "[AI::Client] LLM error: #{e.message}"
      raise
    end
  end
end

# Controller decides how to handle
def chat
  response = client.chat(...)
rescue AI::RateLimitError => e
  render json: { error: "Rate limited, please try again" }, status: 429
rescue AI::Error => e
  render json: { error: "AI service error" }, status: 503
end
```

---

### Caching Strategy

**Cache at ContentGenerator level** (intent-based):

```ruby
module AI
  class ContentGenerator
    def generate_advisor_response(advisor:, conversation:, context: {})
      cache_key = build_cache_key("advisor_response", advisor, conversation, context)

      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        client = build_client(advisor)
        response = client.chat(messages: build_messages(...))
        response.content
      end
    end

    private

    def build_cache_key(prefix, *components)
      # Build deterministic cache key
    end
  end
end
```

**Why here:**
- Intent-based: "advisor response for conversation X" not "raw LLM call"
- Easy to invalidate when conversation changes
- Controllers don't know about caching

---

### TokenUsage Auto-Tracking

**Automatic on every Client call:**

```ruby
module AI
  class Client
    def chat(...)
      response = @ruby_llm_chat.complete

      # Auto-create usage record
      TokenUsage.create!(
        conversation: @context[:conversation],
        advisor: @context[:advisor],
        model: @model.identifier,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        cost: calculate_cost(response)
      )

      normalize_response(response)
    end
  end
end
```

---

## Next Steps

1. **Approve this iteration** - Confirm decisions above are correct
2. **Start implementation** - Phase 1: Build parallel in `app/ai/`
3. **First milestone** - Create `AI::Client`, `AI::Model`, and one tool
4. **Proof of concept** - Migrate one controller action to use new system
5. **Iterate** - Adjust based on what we learn

**Ready to start building?** Or do any decisions need adjustment?
