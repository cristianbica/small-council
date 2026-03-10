# AI Runtime Flow

This page explains the current runtime path for AI-generated responses, tool traces, interaction recording, and UI updates.

## Main conversation path

1. User posts a message in `MessagesController#create`.
2. Controller invokes `AI.runtime_for_conversation(@conversation).user_posted(@message)`.
3. Runtime class (`OpenConversationRuntime`, `ConsensusConversationRuntime`, or `BrainstormingConversationRuntime`) chooses responders, creates `pending` placeholders, and stores parent `pending_advisor_ids`.
4. Runtime requests the first advisor response through `AI.generate_advisor_response(..., async: true)`.
5. `AI.generate_advisor_response` builds:
	- `AI::Tasks::RespondTask`
	- `AI::Contexts::ConversationContext`
	- `AI::Handlers::ConversationResponseHandler`
	- default `UsageTracker` plus configured tracker (`ModelInteractionTracker`)
6. Async execution is enqueued to `AIRunnerJob`, which calls `AI::Runner`.
7. Runner executes the task; model callbacks feed interaction/tool tracking.
8. `ConversationResponseHandler` updates advisor message content/status and calls runtime `advisor_responded` to continue sequencing.

## Utility form-filler path

1. `FormFillersController#create` calls `AI.generate_text(..., async: true)`.
2. `AI.generate_text` builds `AI::Tasks::TextTask` with `AI::Contexts::SpaceContext`.
3. Async work runs via `AIRunnerJob` + `AI::Runner`.
4. `AI::Handlers::TurboFormFillerHandler` broadcasts `success`/`error` to `form_filler_result_<filler_id>`.
5. `form_filler_controller.js` applies returned payload to marked fields.

## Tracking and persistence

- `AI::Trackers::UsageTracker` writes `UsageRecord` when token usage is available.
- `AI::Trackers::ModelInteractionTracker` writes `ModelInteraction` rows and mirrors tool traces to `messages.tool_calls`.
- Tracking failures are rescue-and-log so they do not break message generation.

## UI update path

- Message updates stream on `conversation_<conversation_id>` from message model broadcasts.
- Interaction modal is lazy-loaded through `MessagesController#interactions`, rendering `app/views/messages/interactions.html.erb`.
- `ModelInteraction` broadcasts list/count updates while the modal is open.

## Runtime boundaries

- `MessagesController`: accept user input and start runtime flow.
- `AI::Runtimes::*ConversationRuntime`: select responders and advance turn order.
- `AI::Runner`: execute task/context/handler/tracker graph.
- `AI::Tasks::*`: prompt/message preparation per workload type.
- `AI::Handlers::*`: persist/broadcast post-run outcomes.
- `AI::Trackers::*`: telemetry and observability side effects.
- Advisor and retry generation paths run through `AI.generate_advisor_response(..., async: true)` -> `AIRunnerJob` -> `AI::Runner`.
