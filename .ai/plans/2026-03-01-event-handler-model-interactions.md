# Plan: Replace OTel with RubyLLM Event Handlers for ModelInteraction

Date: 2026-03-01
Type: refactor

## Goal

Eliminate the OpenTelemetry monkey-patch (`RubyLLMCompletePatch`), the OTel SDK, the custom `AI::ModelInteractionSpanProcessor`, and thread-local context passing. Replace with RubyLLM's native chat event handlers (`on_end_message`, `on_tool_call`, `on_tool_result`), registered in `AI::Client#build_ruby_llm_chat`, to create `ModelInteraction` records for both LLM completions and tool executions.

## Non-goals

- Changing the UI modal that displays model interactions (beyond naturally showing tool interactions in the existing list)
- Changing the `UsageRecord` / `track_usage` system
- Recording interactions for the streaming path (parity with current behavior — streaming is skipped today)
- Adding external observability/tracing (can add later independently)

## Scope + assumptions

- OTel gems were added **solely** for ModelInteraction recording — confirmed by grep: no app code references `OpenTelemetry` outside the initializer and span processor
- The `on_end_message` callback in RubyLLM 1.12.1 receives a `RubyLLM::Message` with `input_tokens`, `output_tokens`, `model_id`, `content`, `tool_calls`, `role` (verified in source: `chat.rb:161`)
- The chat object's `@messages` array and `@model`/`@temperature` are accessible inside the handler via closure over the chat instance
- `on_end_message` fires **multiple times** during tool-call loops:
  - Once after each assistant response (line 161: `@on[:end_message]&.call(response)`)
  - Once after each tool result message (line 207: `@on[:end_message]&.call(message)`)
  - **Decision**: Record assistant responses (`role: :assistant`) as `interaction_type: "chat"`. Skip `:tool` role messages from `on_end_message` — tool executions are recorded separately via `on_tool_call`/`on_tool_result`.
- `on_tool_call` fires when the model decides to call a tool — receives the `tool_call` object with `.name`, `.id`, `.arguments`
- `on_tool_result` fires after tool execution — receives the result
- **Decision**: Pair `on_tool_call` + `on_tool_result` to record tool interactions as `interaction_type: "tool"` with tool name, arguments, and result in the payloads
- Context (`message_id`, `account_id`) flows via closure — no thread-locals needed
- The handler has access to the full `@messages` array at callback time, giving us the complete conversation for `request_payload`

## Steps

### Step 1: Create `AI::ModelInteractionRecorder`

Create `app/libs/ai/model_interaction_recorder.rb` — a simple class that encapsulates ModelInteraction creation logic, extracted from the SpanProcessor but without any OTel dependency.

```ruby
# frozen_string_literal: true

module AI
  class ModelInteractionRecorder
    def initialize(message_id:, account_id:)
      @message_id = message_id
      @account_id = account_id
      @started_at = nil
      @pending_tool_call = nil  # Holds on_tool_call data until on_tool_result fires
    end

    # Call before ruby_llm_chat.complete to start timing
    def start_timing
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # on_end_message callback — records LLM completion interactions.
    # chat: the RubyLLM::Chat instance (for @messages, @model, @temperature)
    # response: the RubyLLM::Message passed to on_end_message
    def record_chat(chat:, response:)
      return unless recordable?
      return unless response&.role == :assistant

      duration_ms = compute_duration_ms

      create_interaction!(
        interaction_type: "chat",
        request_payload: build_chat_request_payload(chat, response),
        response_payload: build_chat_response_payload(response),
        model_identifier: chat.model&.id,
        input_tokens: response.input_tokens || 0,
        output_tokens: response.output_tokens || 0,
        duration_ms: duration_ms
      )

      # Reset timer for next round-trip (tool call loops)
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue => e
      Rails.logger.error "[AI::ModelInteractionRecorder] Failed to record chat: #{e.message}"
    end

    # on_tool_call callback — stashes tool call data and starts timing.
    # tool_call: RubyLLM tool call object with .name, .id, .arguments
    def record_tool_call(tool_call)
      @pending_tool_call = {
        name: tool_call.name,
        id: tool_call.id,
        arguments: tool_call.arguments,
        started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }
    end

    # on_tool_result callback — pairs with the pending tool call to record the interaction.
    # result: the tool execution result
    def record_tool_result(result)
      return unless recordable?
      return unless @pending_tool_call

      tool_data = @pending_tool_call
      @pending_tool_call = nil

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_data[:started_at]
      duration_ms = (elapsed * 1000).round(1)

      result_content = result.is_a?(RubyLLM::Tool::Halt) ? result.content.to_s : result.to_s

      create_interaction!(
        interaction_type: "tool",
        request_payload: {
          tool_name: tool_data[:name],
          tool_call_id: tool_data[:id],
          arguments: tool_data[:arguments]
        },
        response_payload: {
          tool_name: tool_data[:name],
          result: result_content
        },
        model_identifier: nil,
        input_tokens: 0,
        output_tokens: 0,
        duration_ms: duration_ms
      )
    rescue => e
      Rails.logger.error "[AI::ModelInteractionRecorder] Failed to record tool: #{e.message}"
    end

    private

    def recordable?
      @message_id && @account_id
    end

    def create_interaction!(interaction_type:, request_payload:, response_payload:,
                            model_identifier:, input_tokens:, output_tokens:, duration_ms:)
      sequence = ModelInteraction.where(message_id: @message_id).count

      ModelInteraction.create!(
        account_id: @account_id,
        message_id: @message_id,
        sequence: sequence,
        interaction_type: interaction_type,
        request_payload: request_payload,
        response_payload: response_payload,
        model_identifier: model_identifier,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        duration_ms: duration_ms
      )
    end

    def compute_duration_ms
      return nil unless @started_at

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
      (elapsed * 1000).round(1)
    end

    def build_chat_request_payload(chat, response)
      # Messages up to (but not including) this response
      all_messages = chat.messages
      response_index = all_messages.rindex(response)
      input_messages = response_index ? all_messages[0...response_index] : all_messages[0..-2]

      system_messages = input_messages.select { |m| m.role == :system }
      non_system = input_messages.reject { |m| m.role == :system }

      payload = {
        model: chat.model&.id,
        provider: chat.model&.provider,
        temperature: chat.instance_variable_get(:@temperature)
      }

      unless system_messages.empty?
        payload[:system_prompt] = system_messages.map { |m| { type: "text", content: m.content.to_s } }
      end

      unless non_system.empty?
        payload[:messages] = non_system.map { |m| format_message(m) }
      end

      payload.compact
    end

    def build_chat_response_payload(response)
      {
        messages: [format_message(response)],
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        model: response.model_id
      }.compact
    end

    def format_message(message)
      msg = { role: message.role.to_s, parts: [] }
      msg[:parts] << { type: "text", content: message.content.to_s } if message.content
      if message.tool_calls&.any?
        message.tool_calls.each_value do |tc|
          msg[:parts] << { type: "tool_call", id: tc.id, name: tc.name, arguments: tc.arguments }
        end
      end
      msg[:tool_call_id] = message.tool_call_id if message.respond_to?(:tool_call_id) && message.tool_call_id
      msg
    end
  end
end
```

**Design rationale**:
- Encapsulates recording logic in a testable, focused class
- No OTel dependency — pure Ruby
- Records both `"chat"` (LLM completions) and `"tool"` (tool executions) interaction types
- Tool recording pairs `on_tool_call` (stash call data + start timer) with `on_tool_result` (compute duration, record)
- Duration timing via `Process.clock_gettime(Process::CLOCK_MONOTONIC)` (monotonic = immune to system clock changes)
- Same payload format as current SpanProcessor output for chat interactions (preserves UI compatibility)
- Tool payloads include tool name, arguments, call ID, and result
- Same rescue-and-log pattern — recording failures never break AI responses

### Step 2: Wire up event handler in `AI::Client#build_ruby_llm_chat`

Modify `build_ruby_llm_chat` to register `on_end_message` on the chat instance:

```ruby
def build_ruby_llm_chat(context: {})
  ruby_context = RubyLLM.context do |config|
    configure_provider(config)
  end

  chat = ruby_context.chat(model: model.identifier)
  chat.with_instructions(system_prompt) if system_prompt
  chat.with_temperature(temperature) if temperature

  # Convert tools to adapters
  tools.each do |tool|
    adapter = tool.to_ruby_llm_tool
    chat.with_tools(adapter.to_ruby_llm_tool)
    @tool_adapters << adapter
  end

  # Register ModelInteraction recording via event handler
  register_interaction_handler(chat, context)

  chat
end
```

### Step 3: Modify `AI::Client#chat` to remove thread-locals

Replace the thread-local block in `chat` with a clean call. Pass `context` to `build_ruby_llm_chat`:

```ruby
def chat(messages:, context: {}, &stream_handler)
  with_retry do
    @tool_adapters = []
    ruby_llm_chat = build_ruby_llm_chat(context: context)

    # Set context on all tool adapters
    @tool_adapters.each { |adapter| adapter.context = context }

    # Add messages to chat
    messages.each do |msg|
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]
      ruby_llm_chat.add_message(role: role, content: content)
    end

    if stream_handler
      handle_streaming(ruby_llm_chat, stream_handler)
    else
      response = ruby_llm_chat.complete

      track_usage(response, context)
      normalize_response(response)
    end
  end
rescue RubyLLM::RateLimitError => e
  Rails.logger.error "[AI::Client] Rate limited: #{e.message}"
  raise RateLimitError, "AI service rate limited: #{e.message}"
rescue RubyLLM::Error => e
  Rails.logger.error "[AI::Client] LLM error: #{e.message}"
  raise APIError, "AI service error: #{e.message}"
end
```

Add the private method:

```ruby
def register_interaction_handler(chat, context)
  message = context[:message]
  account = context[:account] || context[:space]&.account
  return unless message && account

  recorder = AI::ModelInteractionRecorder.new(
    message_id: message.id,
    account_id: account.id
  )
  recorder.start_timing

  chat.on_end_message do |response|
    recorder.record_chat(chat: chat, response: response)
  end

  chat.on_tool_call do |tool_call|
    recorder.record_tool_call(tool_call)
  end

  chat.on_tool_result do |result|
    recorder.record_tool_result(result)
  end
end
```

**Key insight**: The closure captures `recorder` (which holds message_id and account_id) and `chat` — no thread-locals needed. The recorder is scoped to this single `chat` call. Tool interactions are recorded as paired `on_tool_call`/`on_tool_result` events — the call stashes the tool data, the result completes the pair and writes the record.

### Step 4: Add `interaction_type` column to `model_interactions`

Create migration: `bin/rails generate migration AddInteractionTypeToModelInteractions`

```ruby
class AddInteractionTypeToModelInteractions < ActiveRecord::Migration[8.1]
  def change
    add_column :model_interactions, :interaction_type, :string, null: false, default: "chat"
    add_index :model_interactions, :interaction_type
  end
end
```

Update `app/models/model_interaction.rb`:
```ruby
validates :interaction_type, presence: true, inclusion: { in: %w[chat tool] }
```

Default `"chat"` ensures existing records (if any) remain valid.

### Step 5: Delete OTel files

Delete these files entirely:

1. **`config/initializers/opentelemetry.rb`** — the 109-line file containing `RubyLLMCompletePatch` module and OTel SDK configuration
2. **`app/libs/ai/model_interaction_span_processor.rb`** — the 75-line SpanProcessor class

### Step 6: Remove OTel gems from Gemfile

Remove these lines from `Gemfile`:

```ruby
# OpenTelemetry for LLM call observability
gem "opentelemetry-sdk"
gem "opentelemetry-instrumentation-ruby_llm"
```

Run `bundle install` to update `Gemfile.lock`.

### Step 7: Delete OTel test files

Delete these test files entirely:

1. **`test/ai/unit/model_interaction_span_processor_test.rb`** — 241 lines, tests the deleted SpanProcessor
2. **`test/ai/unit/ruby_llm_complete_patch_test.rb`** — 158 lines, tests the deleted monkey-patch

### Step 8: Update `test/ai/unit/client_test.rb`

Remove these 3 tests that verify thread-local behavior:
- `"chat sets thread-local context for OTel span processor"` (lines 348–389)
- `"chat does not set message_id thread-local when no message in context"` (lines 391–422)
- `"thread-local context is cleaned up even on error"` (lines 424–453)

Remove the comment block about OTel delegation (lines 338–346).

Add new tests for event-handler-based recording:

```ruby
test "chat creates ModelInteraction via on_end_message handler" do
  client = Client.new(model: @llm_model, system_prompt: "Be helpful")

  council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
  conversation = @account.conversations.create!(council: council, user: @user, title: "Test")
  message = @account.messages.create!(conversation: conversation, sender: @user, role: "user", content: "Hello")

  # Build a mock chat that captures and fires the on_end_message handler
  mock_response = RubyLLM::Message.new(
    role: :assistant, content: "Hi!", model_id: "gpt-4",
    input_tokens: 100, output_tokens: 50
  )

  registered_handler = nil
  mock_chat = Object.new
  mock_chat.define_singleton_method(:with_instructions) { |*| self }
  mock_chat.define_singleton_method(:with_temperature) { |*| self }
  mock_chat.define_singleton_method(:add_message) { |**| self }
  mock_chat.define_singleton_method(:on_end_message) { |&block| registered_handler = block; self }
  mock_chat.define_singleton_method(:model) { stub(id: "gpt-4", provider: "openai") }
  mock_chat.define_singleton_method(:messages) { [mock_response] }
  mock_chat.define_singleton_method(:complete) do
    registered_handler&.call(mock_response)
    mock_response
  end

  # ... stub RubyLLM.context to return mock_chat ...

  assert_difference "ModelInteraction.count", 1 do
    client.chat(
      messages: [{ role: "user", content: "Hello" }],
      context: { message: message, account: @account, space: @space }
    )
  end

  interaction = ModelInteraction.last
  assert_equal message.id, interaction.message_id
  assert_equal @account.id, interaction.account_id
  assert_equal "gpt-4", interaction.model_identifier
  assert_equal 100, interaction.input_tokens
  assert_equal 50, interaction.output_tokens
end

test "chat does not create ModelInteraction without message in context" do
  # ... similar setup, no message in context, assert_no_difference ...
end

test "ModelInteraction recording failure does not break chat" do
  # ... stub ModelInteraction.create! to raise, assert response still returned ...
end
```

### Step 9: Create `test/ai/unit/model_interaction_recorder_test.rb`

Test the recorder in isolation:

**Chat recording tests:**
- `"records assistant response with correct payloads"`
- `"skips tool messages (role: :tool) in on_end_message"`
- `"skips when message_id is nil"`
- `"skips when account_id is nil"`
- `"increments sequence for multiple interactions on same message"`
- `"computes duration_ms from monotonic clock"`
- `"does not raise on recording failure"`
- `"builds correct request_payload with system prompt, messages"`
- `"builds correct response_payload with tokens and model"`

**Tool recording tests:**
- `"records tool call with name, arguments, and result"`
- `"records tool interaction_type as 'tool'"`
- `"computes tool duration_ms from call to result"`
- `"handles Tool::Halt result"`
- `"skips tool result when no pending tool call"`
- `"does not raise on tool recording failure"`

**Sequencing tests:**
- `"sequences chat and tool interactions correctly across a tool-call loop"`

### Step 10: Update documentation

**`.ai/docs/features/model-interactions.md`** — Rewrite the "Recording via OpenTelemetry" section:
- Replace with "Recording via Event Handlers"
- Document the `AI::ModelInteractionRecorder` class
- Document the `on_end_message` handler registration in `AI::Client`
- Update the flow diagram to show closure-based context instead of thread-locals
- Remove references to OTel, SpanProcessor, thread-locals
- Update the test commands section

**`.ai/docs/patterns/opentelemetry.md`** — Delete this file entirely. OTel is no longer used.

**`.ai/docs/patterns/README.md`** — Remove the OpenTelemetry entry from the Infrastructure Patterns list.

**`.ai/MEMORY.md`** — Update:
- Remove lines 110-111 (OTel gems and complete patch entries)
- Update line 74: change "OTel SpanProcessor" to "event-handler recorder" description
- Add note about `AI::ModelInteractionRecorder`

**`.ai/docs/TODO.md`** — Remove the "ModelInteraction via OpenTelemetry" section (lines 6-10) — this is resolved.

## Verification

1. `bundle install` — confirms OTel gems removed cleanly
2. `bin/rails test` — full suite passes, 0 failures
3. `bin/rails test test/ai/unit/model_interaction_recorder_test.rb` — new recorder tests pass
4. `bin/rails test test/ai/unit/client_test.rb` — updated client tests pass
5. `bin/rails test test/models/model_interaction_test.rb` — existing model tests unaffected
6. Verify no references to `OpenTelemetry`, `RubyLLMCompletePatch`, `ModelInteractionSpanProcessor`, `ai_client_message_id`, or `ai_client_account_id` remain in app/lib/config code (grep check)
7. Manual smoke test: trigger an advisor response → `ModelInteraction` record created with full payloads → UI modal displays correctly

## Doc impact

- **Delete**: `.ai/docs/patterns/opentelemetry.md`
- **Update**: `.ai/docs/features/model-interactions.md`
- **Update**: `.ai/docs/patterns/README.md`
- **Update**: `.ai/MEMORY.md`
- **Update**: `.ai/docs/TODO.md`

## Rollback

1. `git revert <commit>` — single commit restores all deleted/modified files
2. `bundle install` — re-adds OTel gems
3. No migration needed — `ModelInteraction` table is unchanged
