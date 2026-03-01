# Plan: Fix OTel-based ModelInteraction recording

Date: 2026-03-01
Type: bug

## Goal

Fix `ModelInteraction` records not being created when LLM calls happen. The OTel instrumentation gem patches `RubyLLM::Chat#ask`, but our `AI::Client` calls `RubyLLM::Chat#complete` directly — the patch never fires.

## Root cause (evidence-based)

### What the OTel gem patches

The gem (`opentelemetry-instrumentation-ruby_llm` v0.2.0) patches **only** `RubyLLM::Chat#ask`:

```ruby
# gems/opentelemetry-instrumentation-ruby_llm-0.2.0/lib/.../patches/chat.rb:8
def ask(message, &block)
  # ... creates span with gen_ai.operation.name = "chat"
  result = super  # calls original ask → which calls complete
  # ... sets span attributes
end
```

It does NOT patch `complete`.

### How RubyLLM::Chat works

```ruby
# gems/ruby_llm-1.12.1/lib/ruby_llm/chat.rb:34-37
def ask(message = nil, with: nil, &)
  add_message role: :user, content: build_content(message, with)
  complete(&)    # ask is a thin wrapper around complete
end
```

`ask` = add user message + call `complete`. They're two different methods.

### How our client calls RubyLLM

```ruby
# app/libs/ai/client.rb:63-77
messages.each do |msg|
  ruby_llm_chat.add_message(role: role, content: content)   # manually adds messages
end
response = ruby_llm_chat.complete   # calls complete directly, NOT ask
```

Our client manually adds messages via `add_message`, then calls `complete` directly. This **bypasses** the OTel-patched `ask` method entirely. The span is never created, so `ModelInteractionSpanProcessor#on_finish` is never called.

### Why the SpanProcessor + initializer are correct

- `config/initializers/opentelemetry.rb`: Correctly configures `OpenTelemetry::SDK`, registers the SpanProcessor, and calls `c.use` with `capture_content: true`. ✅
- `app/libs/ai/model_interaction_span_processor.rb`: Correctly filters for `gen_ai.operation.name == "chat"` spans, reads Thread-locals for context, creates `ModelInteraction` records. ✅
- `AI::Client#chat`: Correctly sets Thread-locals (`ai_client_message_id`, `ai_client_account_id`) before calling `complete`. ✅

Everything is wired correctly — the one problem is the OTel gem doesn't instrument the method we actually call.

### Version compatibility

- `ruby_llm` 1.12.1 — has both `ask` and `complete` on `RubyLLM::Chat`
- `opentelemetry-instrumentation-ruby_llm` 0.2.0 — only patches `ask`
- `RubyLLM.context` returns a `RubyLLM::Context` whose `.chat` creates a normal `RubyLLM::Chat` — so the prepend does apply to our chat objects. The patch is present, it just instruments the wrong method for our usage.

## Non-goals

- Modifying the upstream OTel gem (we can upstream a PR later)
- Changing `AI::Client` to use `ask` instead of `complete` (it uses `complete` deliberately — it pre-populates messages including system prompts and multi-turn history)
- Adding external OTel trace export
- Changing streaming path behavior

## Scope + assumptions

- Only `AI::Client#chat` non-streaming path needs fixing (streaming has no usage data)
- The fix should be a local patch that wraps `complete` with the same OTel span logic the gem uses for `ask`
- When the upstream gem adds `complete` support, we can remove our patch

## Steps

### Step 1: Create a local patch for `RubyLLM::Chat#complete`

Create `config/initializers/ruby_llm_otel_patch.rb` that prepends a `complete` wrapper to `RubyLLM::Chat`, mirroring the gem's `ask` patch but for `complete`:

```ruby
# frozen_string_literal: true

# Local patch: the opentelemetry-instrumentation-ruby_llm gem (v0.2.0) only
# instruments RubyLLM::Chat#ask, but AI::Client calls #complete directly.
# This patch adds the same OTel span instrumentation to #complete.
#
# Remove when the upstream gem instruments #complete natively.

Rails.application.config.after_initialize do
  next unless defined?(OpenTelemetry::Instrumentation::RubyLLM)

  instrumentation = OpenTelemetry::Instrumentation::RubyLLM::Instrumentation.instance
  next unless instrumentation.installed?

  RubyLLM::Chat.prepend(Module.new do
    def complete(&block)
      provider = @model&.provider || "unknown"
      model_id = @model&.id || "unknown"

      attributes = {
        "gen_ai.operation.name" => "chat",
        "gen_ai.provider.name" => provider,
        "gen_ai.request.model" => model_id
      }

      tracer = instrumentation.tracer

      tracer.in_span("chat #{model_id}", attributes: attributes,
                      kind: OpenTelemetry::Trace::SpanKind::CLIENT) do |span|
        result = super(&block)

        if @messages.last
          response = @messages.last
          span.set_attribute("gen_ai.response.model", response.model_id) if response.model_id
          span.set_attribute("gen_ai.usage.input_tokens", response.input_tokens) if response.input_tokens
          span.set_attribute("gen_ai.usage.output_tokens", response.output_tokens) if response.output_tokens
          span.set_attribute("gen_ai.request.temperature", @temperature) if @temperature

          if capture_content?
            system_messages = @messages.select { |m| m.role == :system }
            input_messages = @messages[0..-2].reject { |m| m.role == :system }

            unless system_messages.empty?
              span.set_attribute("gen_ai.system_instructions",
                system_messages.map { |m| { type: "text", content: m.content.to_s } }.to_json)
            end

            span.set_attribute("gen_ai.input.messages", format_input_messages(input_messages))
            span.set_attribute("gen_ai.output.messages", format_output_messages([response]))
          end
        end

        result
      end
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e)
      super(&block)
    end

    private

    def capture_content?
      env_value = ENV["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"]
      return env_value.to_s.strip.casecmp("true").zero? unless env_value.nil?

      OpenTelemetry::Instrumentation::RubyLLM::Instrumentation.instance.config[:capture_content]
    end

    def format_input_messages(messages)
      messages.map { |m| format_single_message(m) }.to_json
    end

    def format_output_messages(messages)
      messages.map { |m| format_single_message(m) }.to_json
    end

    def format_single_message(message)
      msg = { role: message.role.to_s, parts: [] }
      msg[:parts] << { type: "text", content: message.content.to_s } if message.content
      if message.tool_calls&.any?
        message.tool_calls.each_value do |tc|
          msg[:parts] << { type: "tool_call", id: tc.id, name: tc.name, arguments: tc.arguments }
        end
      end
      msg[:tool_call_id] = message.tool_call_id if message.tool_call_id
      msg
    end
  end)
end
```

**Why a separate initializer?** The OTel initializer (`config/initializers/opentelemetry.rb`) configures the SDK and registers the gem's instrumentation. This second initializer patches `complete` after the gem's `install` block has run and prepended `ask`. Initializer load order is alphabetical, so `opentelemetry.rb` runs before `ruby_llm_otel_patch.rb`. The `after_initialize` callback ensures RubyLLM is fully loaded.

**Why not modify `AI::Client` to call `ask`?** Our client manually assembles multi-turn conversation history (system prompts, prior messages) via `add_message`, then calls `complete`. Using `ask` would require passing only the last user message and restructuring how history is managed. That's a larger refactor with more risk.

### Step 2: Prevent double-spanning when `ask` calls `complete`

The gem's `ask` patch wraps `ask`, and `ask` internally calls `complete`. With our patch, calling `ask` would create two spans (one from the gem's `ask` patch, one from our `complete` patch). This doesn't affect our code (we never call `ask`), but for safety (e.g., `test_connection` in `AI::Client` uses `chat.ask`), add a guard:

```ruby
def complete(&block)
  # Skip if already inside an ask span (ask calls complete internally)
  if Thread.current[:ruby_llm_otel_in_ask_span]
    return super(&block)
  end
  # ... rest of instrumentation
end
```

And in the `ask` patch from the gem — actually, we don't control that. Instead, use a simpler approach: check if there's already an active span for this chat:

```ruby
def complete(&block)
  # If called from within ask(), the gem's ask patch already created a span.
  # Detect this by checking if there's an active span with our attributes.
  current_span = OpenTelemetry::Trace.current_span
  if current_span != OpenTelemetry::Trace::Span::INVALID &&
     current_span.name&.start_with?("chat ")
    return super(&block)
  end
  # ... rest of instrumentation
end
```

**Simpler alternative:** Since our codebase never calls `ask` in the production path (only in `test_connection` which doesn't set Thread-locals for ModelInteraction recording), the double-span is harmless. We can skip this guard for now and add it only if it causes problems.

**Recommended:** Skip the guard for v1. Add a code comment noting the potential double-span.

### Step 3: Update tests

Add a test in `test/ai/unit/model_interaction_span_processor_test.rb` (or a new test file for the patch) that verifies the full integration:

```ruby
# test/ai/integration/otel_complete_patch_test.rb
class OtelCompletePatchTest < ActiveSupport::TestCase
  test "RubyLLM::Chat#complete is patched with OTel instrumentation" do
    assert RubyLLM::Chat.instance_method(:complete).owner != RubyLLM::Chat,
           "complete should be overridden by the OTel patch"
  end
end
```

Existing `ModelInteractionSpanProcessorTest` tests are valid — they test the processor with mock spans. The processor itself works correctly.

### Step 4: Verify end-to-end

Run `bin/rails test` to confirm no regressions. Then manually test with `bin/rails runner`:

```ruby
# Verify OTel is configured
puts OpenTelemetry.tracer_provider.class
# => OpenTelemetry::SDK::Trace::TracerProvider

# Verify instrumentation is installed
inst = OpenTelemetry::Instrumentation::RubyLLM::Instrumentation.instance
puts inst.installed?
# => true

# Verify complete is patched (check method owner)
puts RubyLLM::Chat.instance_method(:complete).owner
# Should NOT be RubyLLM::Chat (should be our prepended module)
```

## Verification

- `bin/rails test` — all tests pass, 0 failures
- `bin/rails runner` confirms:
  - `OpenTelemetry::Instrumentation::RubyLLM::Instrumentation.instance.installed?` → `true`
  - `RubyLLM::Chat.instance_method(:complete).owner` is not `RubyLLM::Chat`
- Manual test: trigger an advisor response → `ModelInteraction` record created with full payloads

## Doc impact

- Update: `.ai/MEMORY.md` — note the `complete` vs `ask` patch workaround
- Update: `.ai/docs/patterns/opentelemetry.md` (if it exists) — document the local patch
- doc impact: `updated` (MEMORY.md)

## Rollback

1. Delete `config/initializers/ruby_llm_otel_patch.rb`
2. If upstream gem adds `complete` support, just upgrade the gem and remove the file
