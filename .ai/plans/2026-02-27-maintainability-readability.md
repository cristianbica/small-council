# Maintainability & Readability Improvement Plan

**Date:** 2026-02-27
**Status:** DRAFT - Awaiting Approval
**Scope:** Maintainability, Readability, AI Abstraction, Tool Consolidation
**Estimated Duration:** 15 days (3 weeks)
**Target Completion:** 2026-03-20

---

## Executive Summary

This plan addresses **maintainability and readability issues** only, extracted from the comprehensive due diligence plan. It focuses on:

1. **AI Abstraction Layer** - Hide RubyLLM implementation details from controllers
2. **Tool Consolidation** - Merge duplicate tool hierarchies (ScribeTools, RubyLLMTools, AdvisorTools)
3. **God Class Refactoring** - Split AIClient and SpaceScribeController
4. **Readability Improvements** - Naming, logging, magic numbers
5. **Test Coverage** - Add missing service tests

**Excludes:** Security fixes (covered in separate plan)

---

## Current Problems

### 1. AI Implementation Details Leaked into Controllers

**Problem:** Controllers know too much about RubyLLM:

```ruby
# app/controllers/space_scribe_controller.rb (current)
chat = context.chat(model: scribe_model.identifier).with_tools(
  RubyLLMTools::CreateMemoryTool,
  RubyLLMTools::QueryMemoriesTool,
  # ... 5 more tools
)
chat.with_instructions(system_prompt)
```

**Issues:**
- Controller knows about `RubyLLM.context`, `RubyLLMTools`, provider config
- Cannot swap AI providers without changing controllers
- Hard to test (requires RubyLLM setup)

### 2. Tool Hierarchy Duplication

**Current State (3 parallel hierarchies):**

```
app/services/
├── ruby_llm_tools/          # 12 files - RubyLLM::Tool subclasses
│   ├── create_memory_tool.rb
│   ├── query_memories_tool.rb
│   └── ask_advisor_tool.rb
├── scribe_tools/             # 4 files - custom tool framework
│   ├── create_memory_tool.rb
│   └── query_memories_tool.rb
└── advisor_tools/            # 4 files - advisor-specific tools
    ├── query_memories_tool.rb
    └── ask_advisor_tool.rb
```

**Problems:**
- 20+ tool files with similar functionality
- Same tool implemented 2-3 times (e.g., QueryMemoriesTool)
- Confusion: which tool class to use when?
- Maintenance burden: change requires updating 2-3 files

### 3. God Classes

| Class | Lines | Methods | Issues |
|-------|-------|---------|--------|
| `AIClient` | 480 | 19+ | Prompt building, API calls, retries, tool execution, response parsing |
| `SpaceScribeController` | 315 | 11 | Prompt building (65 lines inline), business logic |

---

## Goals

1. **Controllers should only say:** "I need an AI client for this model with these tools"
2. **One tool hierarchy:** Consolidate 20+ files into single framework
3. **Service layer responsibility:** AI implementation details hidden behind facade
4. **Testable:** Can mock AI client without RubyLLM dependencies

---

## Phase 1: AI Abstraction Layer (Days 1-5)

### Day 1: Design AI Client Interface (Effort: 4 hours)

**Create:** `app/services/ai/client_factory.rb`

```ruby
module AI
  class ClientFactory
    def self.create(
      model:,
      tools: [],
      system_prompt: nil,
      temperature: 0.7,
      max_tokens: 1000
    )
      # Returns abstract AI client, hides RubyLLM details
    end
  end
end
```

**Create:** `app/services/ai/client.rb` (abstract interface)

```ruby
module AI
  class Client
    def initialize(model, config = {}); end
    def add_message(role:, content:); end
    def complete; end  # Returns AI::Response
    def with_tools(*tools); end
  end
end
```

**Create:** `app/services/ai/response.rb` (value object)

```ruby
module AI
  class Response
    attr_reader :content, :tool_calls, :input_tokens, :output_tokens
    # Normalizes response from different providers
  end
end
```

**Deliverable:** Interface designed, reviewed

### Day 2: Implement RubyLLM Adapter (Effort: 6 hours)

**Create:** `app/services/ai/adapters/ruby_llm_adapter.rb`

```ruby
module AI
  module Adapters
    class RubyLLMAdapter
      def initialize(model_config)
        @model = model_config.identifier
        @provider = model_config.provider
      end

      def create_client
        context = RubyLLM.context do |config|
          configure_provider(config)
        end
        context.chat(model: @model)
      end

      def configure_provider(config)
        case @provider.provider_type
        when "openai"
          config.openai_api_key = @provider.api_key
        when "openrouter"
          config.openrouter_api_key = @provider.api_key
        end
      end
    end
  end
end
```

**Deliverable:** Adapter implemented, unit tests pass

### Day 3: Implement Tool Mapping (Effort: 6 hours)

**Problem:** Controllers currently pass `RubyLLMTools::CreateMemoryTool` directly

**Solution:** Tool registry that maps tool names to implementations

**Create:** `app/services/ai/tool_registry.rb`

```ruby
module AI
  class ToolRegistry
    TOOLS = {
      create_memory: { scribe: ScribeTools::CreateMemoryTool, llm: RubyLLMTools::CreateMemoryTool },
      query_memories: { scribe: ScribeTools::QueryMemoriesTool, llm: RubyLLMTools::QueryMemoriesTool },
      ask_advisor: { advisor: AdvisorTools::AskAdvisorTool, llm: RubyLLMTools::AdvisorAskAdvisorTool },
      # ... etc
    }.freeze

    def self.for_client(client_type, tool_name)
      TOOLS.dig(tool_name, client_type)
    end
  end
end
```

**Deliverable:** Tool registry working, tests pass

### Day 4: Refactor SpaceScribeController (Effort: 6 hours)

**Current (315 lines):**
```ruby
class SpaceScribeController < ApplicationController
  def chat
    # 65 lines of RubyLLM configuration
    context = RubyLLM.context { |c| ... }
    chat = context.chat(model: model.identifier).with_tools(...)
    # ... more implementation details
  end
end
```

**Refactored (< 100 lines):**
```ruby
class SpaceScribeController < ApplicationController
  def chat
    client = AI::ClientFactory.create(
      model: scribe_model,
      tools: [:create_memory, :query_memories, :ask_advisor],  # Just symbols!
      system_prompt: prompt_builder.build
    )

    response = client.complete(messages)
    handle_response(response)
  end
end
```

**Extract:** `app/services/scribe/prompt_builder.rb` (65 lines from controller)

**Deliverable:** Controller < 100 lines, all tests pass

### Day 5: Refactor ConversationsController (Effort: 4 hours)

**Current:** Controllers trigger advisor responses directly with AIClient

**Refactored:** Use same AI::ClientFactory

```ruby
class ConversationsController < ApplicationController
  def create
    # ... create conversation ...

    # Instead of AIClient.new(...)
    client = AI::ClientFactory.create(
      model: advisor.effective_llm_model,
      tools: [:query_memories, :ask_advisor],  # Symbol names only
      system_prompt: advisor.system_prompt
    )

    GenerateResponseJob.perform_later(client: client, conversation: conversation)
  end
end
```

**Deliverable:** Both controllers use abstraction layer

---

## Phase 2: Tool Consolidation (Days 6-10)

### Day 6: Analyze Tool Duplication (Effort: 4 hours)

**Audit all 20+ tool files:**

| Tool | ScribeTools | RubyLLMTools | AdvisorTools | Consolidation Strategy |
|------|-------------|--------------|--------------|----------------------|
| CreateMemory | ✅ | ✅ | ❌ | Keep one, adapter for other |
| QueryMemories | ✅ | ✅ | ✅ | Merge all three |
| AskAdvisor | ❌ | ✅ | ✅ | Merge advisor + LLM |
| BrowseWeb | ✅ | ✅ | ❌ | Keep one |
| FinishConversation | ✅ | ❌ | ❌ | Keep |

**Deliverable:** Consolidation plan documented

### Day 7: Create Unified Tool Base (Effort: 6 hours)

**Create:** `app/services/tools/base_tool.rb`

```ruby
module Tools
  class BaseTool
    def initialize(context); end

    def name
      self.class.name.demodulize.underscore.gsub('_tool', '')
    end

    def description
      raise NotImplementedError
    end

    def parameters
      raise NotImplementedError
    end

    def execute(params)
      raise NotImplementedError
    end

    def to_function_definition
      # Returns format for both RubyLLM and custom frameworks
      {
        name: name,
        description: description,
        parameters: parameter_schema
      }
    end
  end
end
```

**Deliverable:** Base class created, tests pass

### Day 8: Consolidate QueryMemoriesTool (Effort: 6 hours)

**Current:** 3 implementations
- `ScribeTools::QueryMemoriesTool`
- `RubyLLMTools::QueryMemoriesTool`
- `AdvisorTools::QueryMemoriesTool`

**New:** Single implementation with adapters

```ruby
# app/services/tools/query_memories_tool.rb
module Tools
  class QueryMemoriesTool < BaseTool
    def description
      "Query the memory system for relevant context..."
    end

    def parameters
      {
        query: { type: :string, required: true },
        limit: { type: :integer, default: 5 }
      }
    end

    def execute(query:, limit: 5)
      # Single implementation
      MemorySearch.new(context.space, query, limit: limit).execute
    end
  end
end

# Adapter for RubyLLM
module Tools
  module Adapters
    class RubyLLMAdapter < RubyLLM::Tool
      def initialize(tool_instance)
        @tool = tool_instance
      end

      def execute(**params)
        @tool.execute(params)
      end
    end
  end
end
```

**Deliverable:** One QueryMemoriesTool, tests pass

### Day 9: Consolidate AskAdvisorTool (Effort: 6 hours)

**Merge:**
- `AdvisorTools::AskAdvisorTool` (business logic)
- `RubyLLMTools::AdvisorAskAdvisorTool` (LLM interface)

**New:** Single tool with clear separation

```ruby
# app/services/tools/ask_advisor_tool.rb
module Tools
  class AskAdvisorTool < BaseTool
    def description
      "Ask a question to a specific advisor..."
    end

    def execute(advisor_name:, question:)
      # Single implementation that works for both
      # Scribe and Advisor contexts
      advisor = find_advisor(advisor_name)
      conversation = context.conversation

      create_message(conversation, advisor, question)
      enqueue_response_job(advisor, conversation)
    end
  end
end
```

**Deliverable:** Merged tool, tests pass

### Day 10: Remove Duplicate Tools (Effort: 4 hours)

**Delete:**
- `app/services/scribe_tools/query_memories_tool.rb`
- `app/services/advisor_tools/query_memories_tool.rb`
- `app/services/ruby_llm_tools/advisor_query_memories_tool.rb`
- (Similar for other consolidated tools)

**Update:** All references to use new unified tools

**Verification:** `find app/services -name "*_tool.rb" | wc -l` → Should be ~8-10 (from 20+)

**Deliverable:** 50% reduction in tool files, all tests pass

---

## Phase 3: Readability Improvements (Days 11-13)

### Day 11: Naming Standardization (Effort: 6 hours)

**Rename for clarity:**

| Current | New | Reason |
|---------|-----|--------|
| `RoE` | `RulesOfEngagement` | Full words, clearer |
| `roe_strategy` | `engagement_strategy` | No abbreviation |
| `AIClient` | `AI::Client` | Namespace, clearer |
| `advisor.scribe?` | `advisor.scribe_role?` | Clearer intent |

**Update:** All references, tests, documentation

**Deliverable:** Consistent naming throughout

### Day 12: Remove Excessive Logging (Effort: 6 hours)

**Files to clean:**
- `app/services/roe/round_robin_roe.rb` (10+ debug logs in 60 lines)
- `app/services/roe/moderated_roe.rb`
- `app/services/conversation_lifecycle.rb`

**Strategy:**
- Keep: Error logs, warning logs, key info logs
- Remove: Debug logs (or use block form for lazy eval)
- Use: Structured logging with context

**Before:**
```ruby
Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Step 1: Checking for @mentions..."
mentioned = parse_mentions(message&.content)
Rails.logger.debug "[RoE::RoundRobinRoE#determine_responders] Found mentions: #{mentioned.inspect}"
```

**After:**
```ruby
# Removed - use Rails.logger.debug { "..." } if needed for performance
mentioned = parse_mentions(message&.content)
Rails.logger.info "[RoundRobin] Mentioned advisors: #{mentioned.map(&:name).join(', ')}" if mentioned.any?
```

**Deliverable:** Log volume reduced by 70%

### Day 13: Extract Magic Numbers (Effort: 4 hours)

**Create:** `app/services/ai/configuration.rb`

```ruby
module AI
  class Configuration
    CONTEXT_LIMITS = {
      memory_context_length: 2000,
      conversation_history_limit: 20,
      web_content_max_length: 50_000,
      generation_max_tokens: 2000,
      default_temperature: 0.7,
      max_retries: 2,
      retry_delay_seconds: 1
    }.freeze

    def self.[](key)
      CONTEXT_LIMITS[key]
    end
  end
end
```

**Replace all magic numbers:**
- `app/services/ai_client.rb` lines 9, 42, 262, 297, 316, 322
- `app/services/memory_search.rb` line 7
- `app/services/web_browser_service.rb` line 11
- `app/controllers/space_scribe_controller.rb` line 87

**Before:**
```ruby
MAX_MEMORY_LENGTH = 2000
messages.last(20)
content[0..50000]
```

**After:**
```ruby
AI::Configuration[:memory_context_length]
AI::Configuration[:conversation_history_limit]
AI::Configuration[:web_content_max_length]
```

**Deliverable:** No magic numbers, all use constants

---

## Phase 4: Testing & Documentation (Days 14-15)

### Day 14: Add Service Tests (Effort: 6 hours)

**Priority test coverage:**

| Service | Current Tests | Target |
|---------|--------------|--------|
| `AI::ClientFactory` | 0 | 100% |
| `AI::Client` | 0 | 100% |
| `Tools::BaseTool` | 0 | 100% |
| `Tools::QueryMemoriesTool` | 0 | 80% |
| `Tools::AskAdvisorTool` | 0 | 80% |
| `Scribe::PromptBuilder` | 0 | 70% |

**Deliverable:** 70%+ coverage for all new services

### Day 15: Documentation (Effort: 6 hours)

**Create:** `.ai/docs/patterns/ai-abstraction.md`

```markdown
# AI Abstraction Pattern

## Goal
Hide RubyLLM implementation details behind clean interface

## Usage
```ruby
client = AI::ClientFactory.create(
  model: llm_model,
  tools: [:query_memories, :ask_advisor],
  system_prompt: "You are a helpful assistant"
)

response = client.complete(messages)
```

## Architecture
- AI::Client - Abstract interface
- AI::Adapters::RubyLLMAdapter - Implementation
- Tools::BaseTool - Unified tool framework
```

**Create:** `.ai/docs/patterns/tool-framework.md`

```markdown
# Tool Framework

## Unified Tool Hierarchy
All tools inherit from Tools::BaseTool

## Creating a New Tool
1. Create class in app/services/tools/
2. Implement name, description, parameters, execute
3. Register in AI::ToolRegistry

## Usage
Controllers use symbol names: `tools: [:query_memories]`
```

**Update:** `.ai/MEMORY.md` with new conventions

**Deliverable:** Documentation complete

---

## Success Criteria

### AI Abstraction
- [ ] Controllers don't reference RubyLLM directly
- [ ] Controllers pass symbol tool names, not class names
- [ ] Can swap AI provider by changing adapter only
- [ ] AI client can be mocked in tests

### Tool Consolidation
- [ ] Tool file count reduced from 20+ to 8-10
- [ ] Single QueryMemoriesTool (not 3 versions)
- [ ] Single AskAdvisorTool (not 2 versions)
- [ ] All tools inherit from Tools::BaseTool

### Readability
- [ ] No `RoE` abbreviation (full `RulesOfEngagement`)
- [ ] Log volume reduced by 70%
- [ ] No magic numbers (all use AI::Configuration)
- [ ] Controller methods < 20 lines

### Testing
- [ ] AI::ClientFactory has 100% test coverage
- [ ] All tools have >70% coverage
- [ ] Controllers have integration tests
- [ ] Total service coverage >70%

---

## File Changes Summary

### New Files (8)
```
app/services/ai/client_factory.rb
app/services/ai/client.rb
app/services/ai/response.rb
app/services/ai/adapters/ruby_llm_adapter.rb
app/services/ai/tool_registry.rb
app/services/ai/configuration.rb
app/services/tools/base_tool.rb
app/services/scribe/prompt_builder.rb
```

### Modified Files (6)
```
app/controllers/space_scribe_controller.rb        # Refactored (< 100 lines)
app/controllers/conversations_controller.rb       # Use AI::ClientFactory
app/services/ai_client.rb                         # Deprecated, redirect to AI::Client
app/services/roe/*.rb                             # Rename to RulesOfEngagement
app/services/ai/configuration.rb                  # Add constants
```

### Deleted Files (12+)
```
app/services/scribe_tools/query_memories_tool.rb
app/services/scribe_tools/create_memory_tool.rb
app/services/advisor_tools/query_memories_tool.rb
app/services/ruby_llm_tools/advisor_*_tool.rb (4 files)
# ... other duplicates
```

### Documentation (2)
```
.ai/docs/patterns/ai-abstraction.md
.ai/docs/patterns/tool-framework.md
```

---

## Dependencies

```
Phase 1: AI Abstraction
├── Day 1: Interface design [NO DEPS]
├── Day 2: RubyLLM adapter [DEP: Day 1]
├── Day 3: Tool registry [DEP: Day 1]
├── Day 4: Refactor controllers [DEP: Day 2, 3]
└── Day 5: Test controllers [DEP: Day 4]

Phase 2: Tool Consolidation
├── Day 6: Audit tools [NO DEPS]
├── Day 7: Base tool class [NO DEPS]
├── Day 8: Consolidate QueryMemories [DEP: Day 7]
├── Day 9: Consolidate AskAdvisor [DEP: Day 7]
└── Day 10: Remove duplicates [DEP: Day 8, 9]

Phase 3: Readability
├── Day 11: Naming [NO DEPS]
├── Day 12: Logging cleanup [NO DEPS]
└── Day 13: Magic numbers [NO DEPS]

Phase 4: Testing & Docs
├── Day 14: Tests [DEP: Phase 1, 2]
└── Day 15: Documentation [DEP: All]
```

---

## Verification Commands

### AI Abstraction
```bash
# Verify no RubyLLM in controllers
grep -r "RubyLLM" app/controllers/ || echo "✅ Controllers clean"

# Verify tool symbols used
grep -r "tools: \[" app/controllers/ | grep -v "Tool" || echo "✅ Using symbols"

# Verify AI namespace exists
ls -la app/services/ai/ || echo "❌ Missing AI directory"
```

### Tool Consolidation
```bash
# Count tool files (should be ~8-10)
find app/services -name "*_tool.rb" | wc -l

# Verify no duplicates
grep -l "class QueryMemoriesTool" app/services -r | wc -l  # Should be 1
```

### Readability
```bash
# No magic numbers in AIClient
grep -E "\b[0-9]{3,}\b" app/services/ai/configuration.rb  # Should show constants

# Check log reduction
grep -c "Rails.logger.debug" app/services/roe/*.rb  # Should be < 10 total
```

### Testing
```bash
# Run new tests
bin/rails test test/services/ai/
bin/rails test test/services/tools/

# Check coverage
cat coverage/index.html | grep "Services" | grep -o "[0-9]*%"
```

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Tool consolidation breaks functionality | Medium | High | Comprehensive test suite, phase rollout |
| AI abstraction adds complexity | Low | Medium | Keep adapter simple, well-documented |
| Controller refactoring breaks UI | Medium | High | Feature tests, staging validation |
| Timeline slips | Low | Medium | Can defer Phase 4 (docs) post-DD |

---

## Rollback Plan

If issues arise:

```bash
# Revert specific refactor
git checkout HEAD -- app/controllers/space_scribe_controller.rb

# Revert to old AIClient temporarily
# (Keep AI::Client alongside for gradual migration)
```

**Gradual Migration Strategy:**
1. Build AI::Client alongside existing AIClient
2. Migrate one controller at a time
3. Remove old AIClient only after all migrated
4. Keep old tool classes until new ones proven

---

## Approval

**This plan requires approval before implementation.**

Please confirm:
1. [ ] 15-day timeline is acceptable
2. [ ] AI abstraction approach is correct
3. [ ] Tool consolidation strategy is acceptable
4. [ ] Rollback plan is sufficient

**Approved by:** _________________  **Date:** _________________

---

## Appendix: Evidence

### Current Controller Coupling
```bash
$ grep -n "RubyLLM" app/controllers/space_scribe_controller.rb
70:  chat = context.chat(model: scribe_model.identifier).with_tools(
71:    RubyLLMTools::CreateMemoryTool,
72:    RubyLLMTools::UpdateMemoryTool,
...
```

### Current Tool Duplication
```bash
$ find app/services -name "query_memories_tool.rb"
app/services/scribe_tools/query_memories_tool.rb
app/services/advisor_tools/query_memories_tool.rb
app/services/ruby_llm_tools/query_memories_tool.rb
```

### Current God Classes
```bash
$ wc -l app/services/ai_client.rb app/controllers/space_scribe_controller.rb
480 app/services/ai_client.rb
315 app/controllers/space_scribe_controller.rb
```

### Excessive Logging
```bash
$ grep -c "Rails.logger" app/services/roe/round_robin_roe.rb
12
```
