# Plan: Model Interactions — Record & View LLM API Calls

Date: 2026-02-28
Type: feature
Status: Completed

## Goal

Give users transparency into LLM API behavior by recording every request/response round-trip for AI-generated messages and exposing them through a per-message modal. This supports debugging, cost awareness, and trust.

## Non-goals

- Retroactive recording of past messages (forward-only)
- Filtering/searching interactions globally (per-message only)
- Admin-only gating (visible to all users)
- Recording interactions for profile/council/memory generation (only message-producing calls)
- Streaming support (streaming path returns no usage data and has different flow)

## Scope + Assumptions

- One new table `model_interactions` with JSONB request/response columns
- Hook recording inside `AI::Client#chat` (the single entry point for all LLM calls)
- Context already carries `message` reference (via `context[:message]`) for advisor responses
- Need to wire `message` through context for scribe followups (currently missing)
- UI: small icon next to advisor messages → DaisyUI `<dialog>` modal (existing pattern)
- No new Stimulus controller needed — uses `<dialog>.showModal()` pattern already in `_message.html.erb`
- No new route or controller needed — interactions are eager-loaded with messages and rendered inline

## Evidence

| File | Finding |
|---|---|
| `app/libs/ai/client.rb:54` | `#chat(messages:, context:)` — single entry point; `context[:message]` used at L229 for usage tracking |
| `app/libs/ai/client.rb:222-253` | `#track_usage` — reference pattern for recording after completion |
| `app/libs/ai/content_generator.rb:168-171` | `client.chat(messages:, context: ctx.merge(context))` — message flows via merged context |
| `app/jobs/generate_advisor_response_job.rb:88-93` | `context: { message: message }` — message passed in context hash |
| `app/jobs/generate_advisor_response_job.rb:96-112` | Scribe followup path: `generate_scribe_followup` does NOT pass message in context — needs fix |
| `app/libs/ai/content_generator.rb:181-200` | `generate_scribe_followup` calls `client.complete(prompt:)` with no context — needs message piped through |
| `app/views/messages/_message_thread.html.erb` | Main message rendering partial — icon goes here |
| `app/views/messages/_message.html.erb:26-35` | Existing debug icon pattern (gear icon, conditional on `prompt_text`) |
| `app/views/messages/_message.html.erb:76-117` | Existing `<dialog>` modal pattern — reuse this structure |
| `app/models/message.rb:11` | `has_one :usage_record` — existing 1:N tracking association pattern |
| `db/schema.rb:235-259` | Messages table schema — `account_id`, `debug_data` JSONB already exists |

## Steps

### Step 1: Migration — Create `model_interactions` table

```ruby
class CreateModelInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :model_interactions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true

      t.integer    :sequence,         null: false, default: 0  # 0, 1, 2... per message
      t.jsonb      :request_payload,  null: false, default: {} # system_prompt, messages, tools, temperature, model
      t.jsonb      :response_payload, null: false, default: {} # content, tool_calls, usage/tokens
      t.string     :model_identifier                            # denormalized for quick display
      t.integer    :input_tokens,     default: 0
      t.integer    :output_tokens,    default: 0
      t.float      :duration_ms                                 # wall-clock time

      t.timestamps
    end

    add_index :model_interactions, [:message_id, :sequence]
    add_index :model_interactions, :account_id
    add_index :model_interactions, :request_payload, using: :gin
    add_index :model_interactions, :response_payload, using: :gin
  end
end
```

**Design decisions:**
- `sequence` integer (not position) — auto-incremented per message, captures ordering of multi-turn tool calls
- JSONB for request/response — flexible, queryable (GIN indexed per convention)
- Denormalized `model_identifier`, `input_tokens`, `output_tokens` — enables quick display without parsing JSONB
- `duration_ms` — useful for latency debugging
- No encryption on payloads — these contain system prompts and conversation context that are already encrypted at the message level; encrypting JSONB would prevent GIN indexing and querying. The data is developer-facing debug info, not user-sensitive PII beyond what's already in the message.

### Step 2: Model — `ModelInteraction`

Create `app/models/model_interaction.rb`:

```ruby
class ModelInteraction < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :message

  validates :account, presence: true
  validates :message, presence: true
  validates :sequence, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :request_payload, presence: true

  scope :chronological, -> { order(sequence: :asc) }

  def total_tokens
    input_tokens + output_tokens
  end
end
```

Add to `Message` model:

```ruby
has_many :model_interactions, dependent: :destroy
```

Add to `Account` model:

```ruby
has_many :model_interactions, dependent: :destroy
```

### Step 3: Recording layer — Hook into `AI::Client#chat`

Modify `AI::Client#chat` to record interactions. The key insight: `ruby_llm_chat.complete` may invoke tool calls internally (RubyLLM handles the tool call loop), so we get back a final response. For the MVP, we record one interaction per `#chat` call. If there are multiple back-and-forth tool calls within a single `complete`, RubyLLM handles them internally and we capture the final aggregated result.

**However**, for true multi-turn recording (where `AI::Client#chat` is called multiple times for one message — e.g., the conversation lifecycle triggers scribe after advisor), each call naturally creates its own `ModelInteraction` with incrementing sequence numbers.

Add `#record_interaction` private method to `AI::Client`:

```ruby
# In AI::Client, after track_usage call in #chat:

def chat(messages:, context: {}, &stream_handler)
  with_retry do
    @tool_adapters = []
    ruby_llm_chat = build_ruby_llm_chat

    @tool_adapters.each { |adapter| adapter.context = context }

    messages.each do |msg|
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]
      ruby_llm_chat.add_message(role: role, content: content)
    end

    if stream_handler
      handle_streaming(ruby_llm_chat, stream_handler)
    else
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = ruby_llm_chat.complete
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)

      track_usage(response, context)
      record_interaction(messages, response, context, duration_ms)  # NEW
      normalize_response(response)
    end
  end
rescue RubyLLM::RateLimitError => e
  # ... existing error handling
end
```

New private method:

```ruby
def record_interaction(messages, ruby_response, context, duration_ms)
  message = context[:message]
  account = context[:account] || context[:space]&.account
  return unless message && account

  # Determine next sequence number
  sequence = ModelInteraction.where(message: message).count

  request_payload = {
    model: model.identifier,
    provider: model.provider.provider_type,
    temperature: temperature,
    system_prompt: system_prompt,
    tools: tools.map { |t| t.class.name },
    messages: messages.map { |m| { role: m[:role] || m["role"], content: (m[:content] || m["content"]).to_s.truncate(500) } },
    messages_count: messages.size
  }

  response_payload = {
    content: ruby_response.content.to_s.truncate(1000),
    tool_calls: ruby_response.tool_calls&.map { |tc| { id: tc.id, name: tc.name, params: tc.params } } || [],
    input_tokens: ruby_response.input_tokens,
    output_tokens: ruby_response.output_tokens,
    model_used: ruby_response.model
  }

  ModelInteraction.create!(
    account: account,
    message: message,
    sequence: sequence,
    request_payload: request_payload,
    response_payload: response_payload,
    model_identifier: model.identifier,
    input_tokens: ruby_response.input_tokens || 0,
    output_tokens: ruby_response.output_tokens || 0,
    duration_ms: duration_ms
  )
rescue => e
  Rails.logger.error "[AI::Client] Failed to record interaction: #{e.message}"
end
```

**Key design decisions:**
- Rescue errors silently (same pattern as `track_usage`) — recording must never break AI responses
- Truncate message content in request payload to 500 chars, response content to 1000 chars — keeps JSONB manageable while providing enough context
- Store tool class names (not full definitions) in request — keeps payload small
- Sequence auto-determined from count — simple, works for concurrent scenarios per-message

### Step 4: Wire message through scribe followup context

**`AI::ContentGenerator#generate_scribe_followup`** — add `context` parameter:

```ruby
def generate_scribe_followup(advisor:, conversation:, message:, context: {})
  # ... existing code ...
  client.complete(
    prompt: prompt,
    context: context.merge(
      message: message,
      space: Current.space,
      conversation: conversation,
      account: conversation.account
    )
  )
end
```

**`AI::Client#complete`** already passes context through to `#chat`:

```ruby
def complete(prompt:, context: {})
  chat(messages: [{ role: "user", content: prompt }], context: context)
end
```

**`GenerateAdvisorResponseJob#generate_scribe_response`** — pass context:

```ruby
def generate_scribe_response(advisor, conversation, message, is_scribe_followup)
  generator = AI::ContentGenerator.new

  if is_scribe_followup
    generator.generate_scribe_followup(
      advisor: advisor,
      conversation: conversation,
      message: message,
      context: { message: message }  # NEW
    )
  else
    # ... existing code already passes context: { message: message }
  end
end
```

### Step 5: Eager-load interactions in conversations controller

In `ConversationsController#show`:

```ruby
def show
  @messages = @conversation.messages.chronological.includes(:sender, :model_interactions)
  @new_message = Message.new
  @available_advisors = available_advisors_for_invite
end
```

### Step 6: UI — Icon + Modal in message thread partial

Modify `app/views/messages/_message_thread.html.erb` to add the interactions icon and modal. Place it next to the existing solved checkmark, after the timestamp:

```erb
<%# After the pending spinner and solved checkmark, add: %>
<% if is_advisor && message.model_interactions.any? %>
  <button onclick="document.getElementById('interactions-modal-<%= message.id %>').showModal()"
          class="btn btn-ghost btn-xs btn-circle opacity-60 hover:opacity-100"
          title="View model interactions (<%= message.model_interactions.size %>)">
    <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
    </svg>
  </button>
<% end %>
```

Add the modal at the end of the turbo_frame_tag block (before `<% end %>`):

```erb
<% if is_advisor && message.model_interactions.any? %>
  <dialog id="interactions-modal-<%= message.id %>" class="modal modal-bottom sm:modal-middle">
    <div class="modal-box max-w-4xl">
      <h3 class="font-bold text-lg mb-4">
        Model Interactions
        <span class="badge badge-neutral badge-sm ml-2"><%= message.model_interactions.size %></span>
      </h3>

      <div class="space-y-6">
        <% message.model_interactions.chronological.each_with_index do |interaction, idx| %>
          <div class="collapse collapse-arrow bg-base-200">
            <input type="checkbox" <%= 'checked' if idx == 0 %> />
            <div class="collapse-title font-medium text-sm">
              <div class="flex items-center gap-3">
                <span class="badge badge-outline badge-sm">#<%= interaction.sequence + 1 %></span>
                <span><%= interaction.model_identifier %></span>
                <span class="text-base-content/50">
                  <%= interaction.input_tokens + interaction.output_tokens %> tokens
                </span>
                <% if interaction.duration_ms %>
                  <span class="text-base-content/50"><%= interaction.duration_ms.round(0) %>ms</span>
                <% end %>
              </div>
            </div>
            <div class="collapse-content space-y-3">
              <div>
                <h4 class="text-xs font-semibold text-base-content/70 mb-1">Request</h4>
                <div class="bg-base-300 p-3 rounded-lg text-xs overflow-x-auto max-h-60 overflow-y-auto">
                  <pre class="whitespace-pre-wrap"><%= JSON.pretty_generate(interaction.request_payload) %></pre>
                </div>
              </div>
              <div>
                <h4 class="text-xs font-semibold text-base-content/70 mb-1">Response</h4>
                <div class="bg-base-300 p-3 rounded-lg text-xs overflow-x-auto max-h-60 overflow-y-auto">
                  <pre class="whitespace-pre-wrap"><%= JSON.pretty_generate(interaction.response_payload) %></pre>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="modal-action">
        <button onclick="document.getElementById('interactions-modal-<%= message.id %>').close()"
                class="btn">Close</button>
      </div>
    </div>
    <form method="dialog" class="modal-backdrop">
      <button>close</button>
    </form>
  </dialog>
<% end %>
```

**Icon choice:** Terminal/code icon (`M8 9l3 3-3 3m5 0h3M5 20h14...`) — visually distinct from the existing gear (debug) icon, communicates "API calls" clearly.

**Modal structure:** DaisyUI `collapse` accordion — first interaction expanded by default, others collapsed. Shows model, tokens, duration in the header. Full request/response JSON in the body.

### Step 7: Fixtures and Tests

#### 7a. Fixture: `test/fixtures/model_interactions.yml`

```yaml
# (empty file or minimal fixture)
# Most tests will create interactions dynamically
```

#### 7b. Model test: `test/models/model_interaction_test.rb`

```ruby
class ModelInteractionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
  end

  test "valid with required attributes" do
    # Create message and interaction inline
  end

  test "requires account" do; end
  test "requires message" do; end
  test "requires sequence" do; end
  test "requires request_payload" do; end
  test "sequence must be non-negative integer" do; end
  test "chronological scope orders by sequence" do; end
  test "total_tokens sums input and output" do; end
  test "belongs to message" do; end
  test "tenant scoping works" do; end
end
```

#### 7c. Integration test: Recording in AI::Client

```ruby
# test/libs/ai/client_interaction_test.rb
class AI::ClientInteractionTest < ActiveSupport::TestCase
  test "chat records model interaction when message in context" do
    # Setup mock RubyLLM, call client.chat with context[:message]
    # Assert ModelInteraction.count increased
    # Assert request/response payloads populated
  end

  test "chat does not record when no message in context" do
    # Call client.chat without context[:message]
    # Assert ModelInteraction.count unchanged
  end

  test "recording failure does not break chat response" do
    # Stub ModelInteraction.create! to raise
    # Assert client.chat still returns response
  end
end
```

#### 7d. View test (integration)

```ruby
# test/integration/model_interactions_display_test.rb
test "advisor message with interactions shows icon" do
  # Create message with model_interactions
  # Visit conversation
  # Assert icon present
end

test "advisor message without interactions shows no icon" do
  # Create message with no interactions
  # Assert no icon
end

test "user message never shows interactions icon" do
  # Assert user messages have no icon
end
```

### Step 8: Update existing debug modal (optional cleanup)

The existing debug modal (lines 76-117 in `_message.html.erb`) uses `prompt_text` and `debug_data`. This overlaps with model interactions. For now, keep both — the debug modal shows the system prompt + summary metadata, while model interactions show the full API payloads. Consider removing the old debug modal in a future cleanup.

Note: The `_message.html.erb` partial is used for Turbo Stream broadcasts (non-threaded view). The `_message_thread.html.erb` partial is used in the conversation show page. Add the icon and modal to **both** partials for consistency.

## Verification

1. **Migration**: `bin/rails db:migrate` succeeds; `bin/rails db:rollback` succeeds
2. **Model tests**: `bin/rails test test/models/model_interaction_test.rb`
3. **Client recording tests**: `bin/rails test test/libs/ai/client_interaction_test.rb`
4. **Full suite**: `bin/rails test` — all ~1396+ existing tests pass (no regressions)
5. **Manual verification**:
   - Start a conversation with an advisor
   - Post a message that triggers advisor response
   - After response completes, verify terminal/code icon appears next to advisor message
   - Click icon → modal opens showing interaction(s)
   - Verify request payload shows model, temperature, messages
   - Verify response payload shows content, tokens
   - Verify user messages do NOT show the icon
   - Verify old messages (before migration) show no icon (no interactions exist)

## Doc impact

- **Create**: `.ai/docs/features/model-interactions.md` — document the feature, table schema, recording hook, UI
- **Update**: `.ai/docs/features/ai-integration.md` — add reference to model interactions recording
- **Update**: `.ai/MEMORY.md` — add ModelInteraction to model list, note recording pattern

## Rollback

1. `bin/rails db:rollback` removes `model_interactions` table
2. Revert `AI::Client#chat` changes (remove `record_interaction` call and method)
3. Revert `ContentGenerator#generate_scribe_followup` context changes
4. Revert view partial changes (remove icon + modal)
5. Remove `ModelInteraction` model file
6. Remove association lines from `Message` and `Account`

## Trade-offs documented

| Decision | Rationale |
|---|---|
| JSONB over normalized columns | Request/response schemas vary by provider and evolve; JSONB is flexible and queryable with GIN indexes |
| Truncated content in payloads | Full conversation history could be huge; 500/1000 char limits keep storage manageable while providing debugging context |
| No encryption on payloads | Content is already encrypted at message level; JSONB encryption would prevent GIN indexing; this is debug/operational data |
| Record at `AI::Client#chat` level, not RubyLLM internal | We control the boundary; RubyLLM's internal tool loop is opaque but we capture each `#chat` invocation which maps to our logical "interaction" |
| Inline modal (no controller/route) | Interactions are small in number per message; eager-loading is cheap; avoids new controller complexity |
| No Stimulus controller | Vanilla `<dialog>.showModal()` is the existing pattern; no JS behavior needed beyond open/close |
