# Plan: Small Council conversation compaction

Date: 2026-03-12

## Goal
- Add a minimal, reversible conversation-compaction flow built around a special scribe message that runs asynchronously, temporarily blocks chat, stores its durable compacted result in `messages.content`, and disappears from normal chat once complete.

## Non-goals
- Change prompt assembly to consume compaction output.
- Redesign later prompt-selection or context-selection architecture.
- Rework historical tool-result replay for normal advisor responses.
- Add a user-facing compaction history browser or management UI.

## Scope + assumptions
- Change type: `feature`.
  - Rationale: compaction does not exist today; this is additive behavior across model, runtime, and UI.
- Use existing message/runtime/Turbo patterns where possible.
- Keep storage on `messages`, not `conversations`.
- Do not add a dedicated compaction-summary column; successful compaction text lives in the compaction message's encrypted `content`.
- Generate compaction with agent `text_writer` and prompt `agents/conversation_compactor` (`app/libs/ai/prompts/agents/conversation_compactor.erb`).
- Reuse `AI::Handlers::ConversationResponseHandler` as the base completion/error handler, with only minimal compaction-specific branching if required.
- Keep completed compaction hidden from normal chat; only pending/running/failed compaction states are user-visible.
- Use simple pressure heuristics for v1 (message count and/or content-length since latest completed compaction), not token-perfect budgeting.

## Evidence basis
- Planning rules/template: `.ai/agents/planner.md`, `.ai/RULES.md`, `.ai/templates/plan.template.md`
- App context: `.ai/docs/overview.md`, `.ai/docs/features/conversation-system.md`, `.ai/docs/features/ai-integration.md`, `.ai/docs/patterns/tasks.md`
- Current implementation points inspected:
  - `app/models/message.rb`
  - `app/models/conversation.rb`
  - `app/controllers/conversations_controller.rb`
  - `app/controllers/messages_controller.rb`
  - `app/views/conversations/_chat.html.erb`
  - `app/views/conversations/_composer.html.erb`
  - `app/views/conversations/_message.html.erb`
  - `app/javascript/controllers/conversation_controller.js`
  - `app/libs/ai.rb`
  - `app/libs/ai/runtimes/conversation_runtime.rb`
  - `app/libs/ai/runtimes/open_conversation_runtime.rb`
  - `app/libs/ai/runtimes/consensus_conversation_runtime.rb`
  - `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb`
  - `app/libs/ai/tasks/respond_task.rb`
  - `app/libs/ai/handlers/conversation_response_handler.rb`
  - `db/schema.rb`

## Acceptance criteria
- A compaction run is represented by a scribe-authored `Message` record, not a conversation-level field.
- The message is identified by the same enum/status pattern already used elsewhere in the app: `message_type: compaction` plus existing `status` values (`pending` -> `responding` -> `complete` / `error`).
- While compaction is `pending` or `responding`, the conversation is chat-blocked server-side and the UI shows a temporary `Compacting...` state.
- Once compaction completes successfully, its compacted result is persisted into that same message record's `content` and the message is excluded from normal chat rendering.
- If compaction fails, the block is cleared and a visible failure message remains in chat.
- `open` conversations compact only from size/history pressure.
- `consensus` and `brainstorming` compact only at round boundaries, gated by size/history pressure.
- No conversation-level compacted-summary field or separate `messages` compaction-text column is introduced.

## Steps
1. **Represent compaction as a normal message using existing model patterns**
   - Add `messages.message_type` (enum/string) with default `chat` and new value `compaction`, following the same enum pattern already used for `Conversation#roe_type`, `Conversation#title_state`, and `Message#status`.
   - Identify a compaction message by `message_type: :compaction`; keep sender/role aligned with existing scribe behavior (`sender` = scribe advisor, `role` = `advisor`).
   - Reuse `messages.content` for every lifecycle phase:
      - `pending` / `responding`: placeholder text such as `Compacting...`
      - `complete`: final compacted summary text
      - `error`: visible failure text
   - Reuse `messages.metadata` only for small orchestration details (for example trigger reason, source window, deferred runtime step), instead of adding conversation-level state or a second text field.
   - Update `Message` with:
      - `enum :message_type, { chat: "chat", compaction: "compaction" }`
      - scopes like `compactions`, `active_compactions`, `completed_compactions`
      - visibility helpers so `visible_in_chat` excludes only `compaction + complete`, but still includes `compaction + pending/responding/error`.

2. **Define the compaction lifecycle around the existing status system**
   - Creation:
      - create a scribe-authored advisor-role message with `message_type: :compaction`, `status: "pending"`, `content: "Compacting..."`.
   - Running:
      - async task flips status to `responding`, preserving the visible placeholder.
   - Complete:
      - handler writes the final summary into `content` and marks `status: "complete"`.
      - completed compaction becomes hidden by scope/UI, not by deleting data.
   - Failed:
      - handler sets `status: "error"` and user-visible `content` like `Compaction failed: ...`.
      - failed compaction remains visible so the block state is explainable.

3. **Generate compaction through the existing text-task path**
   - Add a dedicated compaction task wrapper (for example `AI::Tasks::CompactConversationTask`) only if needed for preparation/state-marking; otherwise prefer a thin wrapper around the existing `TextTask` behavior.
   - Compaction generation should use:
      - agent: `text_writer`
      - prompt: `agents/conversation_compactor`
      - conversation context carrying the conversation, scribe advisor, and target compaction message
   - Add prompt file `app/libs/ai/prompts/agents/conversation_compactor.erb`.
   - Add a small entrypoint helper in `app/libs/ai.rb` (for example `AI.compact_conversation(...)`) to mirror existing task APIs while keeping compaction isolated from normal advisor-reply prompt assembly.

4. **Reuse `ConversationResponseHandler` with minimal compaction-specific adjustments**
   - Keep `AI::Handlers::ConversationResponseHandler` as the base handler because it already owns the message completion/error transition and runtime handoff.
   - Extend it minimally so it can branch on `message.compaction?`:
      - success: normalize/strip response as needed, write final compacted text to `content`, mark complete
      - failure: write an error message to `content`, mark error
      - handoff: notify runtime through a small compaction-aware callback (for example `runtime.compaction_completed(message)` / `runtime.compaction_failed(message)`) or a single `runtime.compaction_finished(message)` branch
   - Avoid introducing a separate compaction-only handler unless reuse proves impossible during implementation.

5. **Add chat blocking as a conversation-level derived state**
   - Add `Conversation#compacting?` / `#chat_blocked?` based on existence of `messages.active_compactions`.
   - Enforce blocking server-side in `MessagesController#create` and `MessagesController#retry` so new user posts or retries cannot start while compaction is active.
   - Render the composer in a disabled state when `conversation.chat_blocked?`, with concise copy like `Compacting conversation...`.
   - Keep server-side blocking as the source of truth; Stimulus is only for affordance, not enforcement.

6. **Trigger compaction with the smallest runtime changes**
   - Introduce a small policy/service object (for example `AI::ConversationCompactionPolicy`) that answers:
      - should compact?
      - why?
     - which deferred follow-up, if any, should resume after completion?
   - Pressure inputs should be simple and local to messages since the latest completed compaction:
     - completed non-compaction message count
     - aggregate content length
   - Trigger rules:
      - `open`: evaluate after a user turn fully resolves; compact only when pressure threshold is exceeded.
      - `consensus` / `brainstorming`: evaluate only at scribe round boundaries (`message_resolved` for completed scribe rounds); compact when boundary is reached and pressure threshold is exceeded.
   - Do not compact mid-turn.

7. **Fit compaction into runtime flow only where needed**
   - `open`: compaction runs after a settled turn, so no automatic resume action is needed.
   - `consensus` / `brainstorming`: store a minimal deferred follow-up in compaction-message metadata (for example `resume_prompt: "consensus_moderator"` or `"force_conclusion"`).
   - On successful compaction, the reused response handler asks the runtime to continue the deferred scribe step.
   - On failed compaction, clear the blocked state and still resume the deferred scribe step so the conversation does not deadlock.

8. **Keep normal chat display simple**
   - Pending/responding compaction renders as a lightweight scribe/system-style indicator in the messages list with `Compacting...` copy.
   - Failed compaction renders as an error bubble.
   - Completed compaction is filtered out by the conversation show query and `Message.visible_in_chat`.
   - Hiding completed compaction should happen on the next Turbo-rendered collection refresh or targeted replacement/removal so the placeholder disappears once complete.
   - No separate compaction history UI in this change.

9. **Document and verify**
   - Update docs for conversation lifecycle, task/handler flow, and the hidden-on-complete compaction behavior.
   - Keep `.ai/MEMORY.md` unchanged unless implementation introduces a durable convention worth remembering (for example the new `message_type` invariant or blocking helper names).

## UI / blocking behavior
- While an active compaction message exists (`pending` or `responding`):
  - composer textarea and submit button are disabled
  - helper copy changes to `Compacting conversation...`
  - retry actions for advisor messages are disabled or suppressed
- The messages list shows the active compaction placeholder/error message like any other visible message, using existing message partial patterns.
- Once compaction completes successfully, the completed compaction message is hidden from normal chat and the composer becomes usable again.

## Likely files / modules to change
- `db/migrate/*add_message_type_to_messages*.rb`
- `app/models/message.rb`
- `app/models/conversation.rb`
- `app/controllers/conversations_controller.rb`
- `app/controllers/messages_controller.rb`
- `app/views/conversations/_chat.html.erb`
- `app/views/conversations/_composer.html.erb`
- `app/views/conversations/_message.html.erb`
- `app/javascript/controllers/conversation_controller.js` (only if needed for disabled-state polish)
- `app/libs/ai.rb`
- `app/libs/ai/tasks/text_task.rb` or `app/libs/ai/tasks/compact_conversation_task.rb`
- `app/libs/ai/handlers/conversation_response_handler.rb`
- `app/libs/ai/runtimes/conversation_runtime.rb`
- `app/libs/ai/runtimes/open_conversation_runtime.rb`
- `app/libs/ai/runtimes/consensus_conversation_runtime.rb`
- `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb`
- `app/libs/ai/prompts/agents/conversation_compactor.erb`
- `app/libs/ai/services` or `app/libs/ai/...` for a compact trigger policy/service object

## Tests to add
- `test/models/message_test.rb`
   - compaction message type helpers/scopes
   - `visible_in_chat` hides only completed compaction messages
- `test/controllers/messages_controller_test.rb`
   - create is rejected while compaction is pending/responding
   - retry is rejected while compaction is pending/responding
   - disabled composer copy renders during compaction
- `test/libs/ai/tasks/text_task_test.rb` or `test/libs/ai/tasks/compact_conversation_task_test.rb`
   - compaction generation uses `text_writer`
   - compaction task/path marks compaction message `responding`
   - compaction task/path prepares expected prompt payload for `agents/conversation_compactor`
- `test/libs/ai/handlers/conversation_response_handler_test.rb`
   - success writes compacted text into `content`, marks complete, and hides from normal chat scope
   - failure marks error and leaves message visible
   - deferred follow-up resumes for round-based runtimes
- `test/libs/ai/runtimes/open_conversation_runtime_test.rb`
   - pressure-based compaction trigger after a settled turn
- `test/libs/ai/runtimes/consensus_conversation_runtime_test.rb`
  - compaction triggers only at round boundary + pressure
  - deferred scribe follow-up resumes after compaction
- `test/libs/ai/runtimes/brainstorming_conversation_runtime_test.rb`
  - same round-boundary behavior as consensus

## Verification
- Run targeted tests:
   - `bin/rails test test/models/message_test.rb`
   - `bin/rails test test/controllers/messages_controller_test.rb`
   - `bin/rails test test/libs/ai/tasks/text_task_test.rb` or `bin/rails test test/libs/ai/tasks/compact_conversation_task_test.rb`
   - `bin/rails test test/libs/ai/handlers/conversation_response_handler_test.rb`
   - `bin/rails test test/libs/ai/runtimes/open_conversation_runtime_test.rb`
   - `bin/rails test test/libs/ai/runtimes/consensus_conversation_runtime_test.rb`
   - `bin/rails test test/libs/ai/runtimes/brainstorming_conversation_runtime_test.rb`
- Manual verification after build:
   - trigger compaction in each RoE mode
   - confirm composer disables while compaction runs
   - confirm completed compaction disappears from normal chat
   - confirm failed compaction remains visible and chat unblocks
   - confirm completed compaction `messages.content` stores the durable compacted result

## Risks / open questions
- Threshold tuning will likely need one follow-up pass.
- Round-boundary detection is simple today (`message_resolved` on completed scribe rounds) but should be verified against real consensus/brainstorming flow.
- If compaction fails repeatedly, the plan currently favors unblocking and continuing conversation rather than hard-stopping.
- The exact compaction prompt shape can stay minimal now, but it should avoid drifting into later prompt-selection redesign.

## Doc impact
- Update:
   - `.ai/docs/features/conversation-system.md`
   - `.ai/docs/features/ai-integration.md`
   - `.ai/docs/patterns/tasks.md`

## Memory impact
- None expected unless implementation establishes a durable repository convention around `Message.message_type` or compaction blocking helpers.

## Rollback (if applicable)
- Remove runtime trigger hooks and chat-blocking guards.
- Leave `message_type` unused or remove it in a follow-up rollback migration.
- Because compaction is isolated to a new message type and a minimal extension of existing task/handler flow, rollback should not require undoing the main chat-response pipeline.

Approve this plan?
