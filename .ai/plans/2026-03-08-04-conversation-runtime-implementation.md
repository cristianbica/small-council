# Plan: ConversationRuntime

Date: 2026-03-08
Status: approved
Change type: refactor
Scope: AI runtime namespace only

## Goal

Replace ConversationLifecycle with clean runtime classes that orchestrate advisor responses.

## Runtime Contract

All runtimes implement:
- `user_posted(message)` - user posted a message
- `advisor_responded(message)` - advisor posted a response
- `message_resolved(message)` - all advisors for a message have responded

Runtime triggers advisor responses via `AI.generate_advisor_response(advisor:, message:, prompt: nil, async: true)` which internally calls `AI::Runner.run`.

Runtime is **purely reactive** - methods called by external actors (to be defined in integration phase).

## Open Mode

**Flow:**
- User posts with @mentions (or 1 advisor implicit) → `user_posted`
- Create pending messages for all mentioned
- Trigger first advisor via `AI.generate_advisor_response(async: true)`
- Advisor responds → `advisor_responded`
- Mark pending resolved, trigger next via `AI.generate_advisor_response(async: true)`
- Last advisor → `message_resolved` (no-op)

**Implementation:**
- `user_posted`: Parse mentions (`Message.extract_mentions`), create pending, trigger first
- `advisor_responded`: Update pending list, find next pending, trigger or resolve
- `message_resolved`: No-op

## Consensus Mode

**Flow:**
- User posts topic → `user_posted`
- No mentions detected → trigger scribe with `:consensus_moderator` prompt via `AI.generate_advisor_response(async: true)`
- Scribe responds (asks for confirmation or mentions advisors) → `advisor_responded`
- If scribe mentions advisors → create pending, trigger first advisor via `AI.generate_advisor_response(async: true)`
- Advisor responds → `advisor_responded` → mark, trigger next or resolve
- All advisors responded → `message_resolved`
- Check: count root resolved scribe messages >= 15?
  - Yes → trigger scribe with `:force_conclusion` prompt via `AI.generate_advisor_response(async: true)`
  - No → trigger scribe with `:consensus_moderator` prompt via `AI.generate_advisor_response(async: true)` (next round)

**State:**
- Round count = count of root messages where sender=scribe, status=resolved
- No DB state stored; derived from message history

**Implementation:**
- `user_posted`: If mentions → Open Mode behavior. Else → trigger scribe
- `advisor_responded`: If scribe → parse mentions, create pending if any. If advisor → mark, trigger next or resolve
- `message_resolved`: If resolved message from scribe → check round limit, trigger scribe with appropriate prompt

## Brainstorming Mode

**Flow:**
- User posts topic + evaluation framework → `user_posted`
- No mentions detected → trigger scribe with `:brainstorming_moderator` prompt via `AI.generate_advisor_response(async: true)`
- Scribe responds (asks for confirmation or requests ideas) → `advisor_responded`
- If scribe requests ideas → create pending, trigger first advisor via `AI.generate_advisor_response(async: true)`
- Advisor responds with idea → `advisor_responded` → mark, trigger next or resolve
- All advisors responded → `message_resolved`
- Check: count root resolved scribe messages >= 15?
  - Yes → trigger scribe with `:force_synthesis` prompt via `AI.generate_advisor_response(async: true)`
  - No → scribe evaluates:
    - Sufficient ideas → trigger scribe with `:final_synthesis` prompt via `AI.generate_advisor_response(async: true)`
    - Need more → trigger scribe with `:brainstorming_moderator` prompt via `AI.generate_advisor_response(async: true)` (next round)
    - Drill into specific idea → trigger scribe with `:drilldown` prompt via `AI.generate_advisor_response(async: true)` on that idea

**State:**
- Round count = count of root messages where sender=scribe, status=resolved
- No DB state stored; derived from message history

**Implementation:**
- `user_posted`: If mentions → Open Mode behavior. Else → trigger scribe
- `advisor_responded`: If scribe → parse mentions/requests, create pending if requesting ideas. If advisor → mark, trigger next or resolve
- `message_resolved`: If resolved message from scribe → check round limit, evaluate sufficiency, trigger scribe with appropriate prompt

## Implementation Details

### Respond Task Adjustments

`AI::Tasks::RespondTask` needs modification to support:
- Dynamic prompt selection based on RoE mode
- Pass prompt symbol to `AI::Runner` (e.g., `:consensus_moderator`)
- Handle scribe vs advisor response generation

Changes:
- Add `prompt` parameter to task initialization
- Modify `prepare(chat)` to load prompt from `AI.prompt(prompt_symbol, context: context)`
- Support system prompt injection (not recorded as message)

### AI Module API

**`AI.generate_advisor_response(advisor:, message:, prompt: nil, async: true)`**
- Public API for triggering advisor/scribe response generation
- Creates context from advisor and message
- Calls `AI::Runner.run(task: :respond, context: context, prompt: prompt, async: async)`
- Used by runtime methods to trigger next response in chain
- Location: `app/libs/ai.rb` module method

**Signature:**
```ruby
def generate_advisor_response(advisor:, message:, prompt: nil, async: true)
  context = AI::Contexts::ConversationContext.new(
    conversation: message.conversation,
    advisor: advisor,
    message: message
  )
  
  AI::Runner.run(
    task: :respond,
    context: context,
    prompt: prompt,
    async: async
  )
end
```

**Base `ConversationRuntime`:**
- `user_posted(message)`: Determines advisors, creates pending messages, triggers first
- `advisor_responded(message)`: Updates pending, triggers next or calls `message_resolved`
- `message_resolved(message)`: Hook for subclasses
- Helpers: `create_pending_messages`, `find_next_pending`, `trigger_advisor_response`, `parse_mentions`

**`OpenConversationRuntime`:**
- Overrides `advisors_to_respond`: Parse mentions or implicit single advisor
- Uses base `message_resolved` (no-op)

**`ConsensusConversationRuntime`:**
- Overrides `advisors_to_respond`: If user message with mentions → Open mode. If no mentions → return empty (wait for scribe). If scribe message → parse scribe mentions
- Overrides `message_resolved`: Count resolved scribe messages, check hard limit, trigger scribe with appropriate prompt

**`BrainstormingConversationRuntime`:**
- Overrides `advisors_to_respond`: Same pattern as Consensus
- Overrides `message_resolved`: Same pattern as Consensus but with synthesis/drilldown logic

### AI::Prompts

Create prompt files (stubs only, content deferred):

- `app/libs/ai/prompts/consensus_moderator.erb` - Instructions for scribe moderating consensus
- `app/libs/ai/prompts/force_conclusion.erb` - Hard limit reached, force conclusion now
- `app/libs/ai/prompts/brainstorming_moderator.erb` - Instructions for scribe leading brainstorming
- `app/libs/ai/prompts/force_synthesis.erb` - Hard limit reached, synthesize now
- `app/libs/ai/prompts/final_synthesis.erb` - Synthesize all ideas into conclusion
- `app/libs/ai/prompts/drilldown.erb` - Explore specific idea in depth

Prompts accessed via `AI.prompt(:symbol, context: context)` and passed to `AI::Runner` as system prompt (not recorded as message).

### AI::Handlers

**`AI::Handlers::ConversationResponseHandler`** (new):
- Called after `AI::Runner` completes an advisor/scribe response
- Receives result from runner
- Calls `runtime.advisor_responded` with the new message
- Handles error cases (retry logic, error messages)

**Handler Flow:**
1. Response generated by `AI::Runner`
2. Handler receives `AI::Result`
3. Handler updates message with response content
4. Handler calls `runtime.advisor_responded(message)`
5. Runtime may trigger next response via `AI.generate_advisor_response` (handler calls API again)
6. Or runtime calls `message_resolved` (handler finishes)

Handler is purely within AI namespace - no integration with existing jobs or controllers.

## Files

**AI Module:**
- `app/libs/ai.rb` - Add `generate_advisor_response` method

**Runtime:**
- `app/libs/ai/runtimes/conversation_runtime.rb` - Base class
- `app/libs/ai/runtimes/open_conversation_runtime.rb` - Open mode
- `app/libs/ai/runtimes/consensus_conversation_runtime.rb` - Consensus mode
- `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb` - Brainstorming mode

**Task:**
- `app/libs/ai/tasks/respond_task.rb` - Modified to support dynamic prompts

**Prompts:**
- `app/libs/ai/prompts/consensus_moderator.erb`
- `app/libs/ai/prompts/force_conclusion.erb`
- `app/libs/ai/prompts/brainstorming_moderator.erb`
- `app/libs/ai/prompts/force_synthesis.erb`
- `app/libs/ai/prompts/final_synthesis.erb`
- `app/libs/ai/prompts/drilldown.erb`

**Handler:**
- `app/libs/ai/handlers/conversation_response_handler.rb` - New handler for orchestrating responses

## Prompts Required

- `app/libs/ai/prompts/consensus_moderator.erb`
- `app/libs/ai/prompts/force_conclusion.erb`
- `app/libs/ai/prompts/brainstorming_moderator.erb`
- `app/libs/ai/prompts/force_synthesis.erb`
- `app/libs/ai/prompts/final_synthesis.erb`
- `app/libs/ai/prompts/drilldown.erb`

Prompt content deferred - create stubs only.

## Out of Scope

- Tests (deferred)
- UI updates (deferred)
- ConversationLifecycle removal (deferred)
- Prompt file content (create stubs only)
- Integration with existing jobs/controllers (parallel infrastructure only)

## Status

Plan includes all infrastructure pieces. Ready for implementation of:
1. AI module API (`generate_advisor_response`)
2. Runtime classes
3. Respond task adjustments
4. Handler
5. Prompt stubs
