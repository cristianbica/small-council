# Plan: Wire Tools to AI::Client in build_client

Date: 2026-02-28
Type: bug

## Goal
Fix `AI::ContentGenerator#build_client` so that tool instances are passed to `AI::Client.new`,
making all advisor tools actually available during conversations.

## Non-goals
- Changing which tools exist or their implementation
- Modifying `build_client_with_system_model` (used for summaries/profile generation — no tools needed)
- Adding new tools
- Changing context building or how context is injected at `chat()` time

## Scope + assumptions
- Scope is strictly `app/libs/ai/content_generator.rb` (one method) plus test additions
- `Advisor#scribe?` returns `is_scribe` (boolean DB column) — already confirmed in `app/models/advisor.rb:25`
- All five tool classes exist and are stateless (no-arg `new`): confirmed by reading each file
- `AI::Client.new` already accepts `tools:` and wires them to the RubyLLM chat — confirmed in `client.rb:41`
- Tools are initialized fresh per `build_client` call (no shared state risk)
- The `@client` memoization guard (`return @client if @client`) is intentional and must be preserved

## Evidence
| File | Finding |
|------|---------|
| `content_generator.rb:296-307` | `build_client` never passes `tools:` — confirmed root cause |
| `client.rb:41` | Constructor signature: `initialize(model:, tools: [], system_prompt: nil, temperature:)` |
| `client.rb:175-179` | Tools are iterated and wired to RubyLLM via `tool.to_ruby_llm_tool` |
| `advisor.rb:25-27` | `scribe?` delegates to `is_scribe` boolean column |
| `generate_advisor_response_job.rb:43` | Job already branches on `advisor.scribe?` |
| `base_tool.rb` | All tools are stateless — instantiated with `.new` |
| `test/ai/unit/content_generator_test.rb` | No existing tests for `build_client`'s tools arg; mock client bypasses it |

## Steps

### 1. Add a private helper `advisor_tools(advisor)` in `content_generator.rb`
Insert after the `build_client_with_system_model` method (after line 319), before
`find_suitable_model`:

```ruby
# Returns the tool instances appropriate for this advisor.
# All advisors get read-only conversation tools.
# Scribe additionally gets write tools (UpdateMemory, FinishConversation).
def advisor_tools(advisor)
  read_only = [
    AI::Tools::Internal::QueryMemoriesTool.new,
    AI::Tools::Conversations::SummarizeConversationTool.new,
    AI::Tools::Conversations::AskAdvisorTool.new
  ]

  if advisor.scribe?
    read_only + [
      AI::Tools::Internal::UpdateMemoryTool.new,
      AI::Tools::Conversations::FinishConversationTool.new
    ]
  else
    read_only
  end
end
```

### 2. Pass `tools:` in `build_client`
Change lines 302-306 in `content_generator.rb` from:

```ruby
Client.new(
  model: model,
  system_prompt: advisor.system_prompt,
  temperature: DEFAULT_TEMPERATURE
)
```

to:

```ruby
Client.new(
  model: model,
  system_prompt: advisor.system_prompt,
  temperature: DEFAULT_TEMPERATURE,
  tools: advisor_tools(advisor)
)
```

### 3. Add tests in `test/ai/unit/content_generator_test.rb`

Add a new test group after the existing `generate_advisor_response` tests (~line 111):

```ruby
# build_client tool wiring tests

test "build_client gives regular advisor read-only tools" do
  generator = ContentGenerator.new
  client = generator.send(:build_client, @advisor)

  tool_classes = client.tools.map(&:class)
  assert_includes tool_classes, AI::Tools::Internal::QueryMemoriesTool
  assert_includes tool_classes, AI::Tools::Conversations::SummarizeConversationTool
  assert_includes tool_classes, AI::Tools::Conversations::AskAdvisorTool
  refute_includes tool_classes, AI::Tools::Internal::UpdateMemoryTool
  refute_includes tool_classes, AI::Tools::Conversations::FinishConversationTool
end

test "build_client gives scribe all tools including write tools" do
  scribe = @space.advisors.create!(
    account: @account,
    name: "Scribe",
    is_scribe: true,
    llm_model: @llm_model
  )

  generator = ContentGenerator.new
  client = generator.send(:build_client, scribe)

  tool_classes = client.tools.map(&:class)
  assert_includes tool_classes, AI::Tools::Internal::QueryMemoriesTool
  assert_includes tool_classes, AI::Tools::Conversations::SummarizeConversationTool
  assert_includes tool_classes, AI::Tools::Conversations::AskAdvisorTool
  assert_includes tool_classes, AI::Tools::Internal::UpdateMemoryTool
  assert_includes tool_classes, AI::Tools::Conversations::FinishConversationTool
end

test "build_client_with_system_model has no tools" do
  generator = ContentGenerator.new
  client = generator.send(:build_client_with_system_model, @account)

  assert_empty client.tools
end

test "advisor_tools returns 3 tools for regular advisor" do
  generator = ContentGenerator.new
  tools = generator.send(:advisor_tools, @advisor)

  assert_equal 3, tools.size
end

test "advisor_tools returns 5 tools for scribe" do
  scribe = @space.advisors.create!(
    account: @account,
    name: "Scribe",
    is_scribe: true,
    llm_model: @llm_model
  )

  generator = ContentGenerator.new
  tools = generator.send(:advisor_tools, scribe)

  assert_equal 5, tools.size
end
```

**Note:** The `scribe` advisor created in these tests omits `system_prompt` because
`Advisor` validation skips `system_prompt presence` when `is_scribe? == true`
(see `advisor.rb:21`).

**Note on memoization:** Existing tests that pass a `mock_client:` via
`ContentGenerator.new(client: mock_client)` are unaffected — `build_client` returns
`@client` immediately when pre-set, so no tool building occurs.

## Verification

```bash
# Run the content generator unit tests
bin/rails test test/ai/unit/content_generator_test.rb

# Run the full AI unit suite to catch regressions
bin/rails test test/ai/

# Run the job tests (GenerateAdvisorResponseJob already branches on scribe?)
bin/rails test test/jobs/generate_advisor_response_job_test.rb

# Full suite smoke check
bin/rails test
```

Manual check: confirm `AI::Client#tools` is non-empty after `build_client` in a console:
```ruby
advisor = Advisor.first
gen = AI::ContentGenerator.new
client = gen.send(:build_client, advisor)
client.tools.map(&:class)
# => [AI::Tools::Internal::QueryMemoriesTool, ...]
```

## Doc impact
doc impact: none — this is an internal implementation fix with no public API or UI change.
The existing `.ai/docs/` entries for AI integration do not document `build_client` internals.

## Rollback
Revert the two-line change to `build_client` (remove `tools: advisor_tools(advisor)`) and
delete the `advisor_tools` helper. Tools default to `[]` in `AI::Client`, so rolling back
restores the previous (broken) behaviour with no side effects.
