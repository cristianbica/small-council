# Plan: App-Owned Tool Approval

Date: 2026-03-06

## Problem / goal
- Users can currently inspect tool usage only after the fact through model-interaction logs.
- The current RubyLLM integration executes tools immediately once the model emits a tool call, so there is no app-owned approval checkpoint before execution.
- Goal: build tool approval inside Small Council, on stock RubyLLM, with durable per-conversation per-advisor per-tool configuration and exact-call approval requests that pause and later resume advisor work.

## Scope
- Add conversation-scoped tool configuration with these states: `not_available`, `ask`, `allowed`.
- Support both advisor-specific and all-advisors-in-conversation policy rows.
- Add exact-call approval requests for `ask` tool invocations.
- Surface proactive policy editing in the existing conversation UI.
- Surface inline approval decisions on the paused advisor message.
- Resume work by re-running the existing background job after user action.

## Non-goals
- No RubyLLM fork, monkey patch, or upstream-first API work.
- No account-wide or space-wide defaults in v1.
- No attempt to persist or resume an in-flight RubyLLM stack frame.
- No standalone approval center or separate settings page.
- No expansion of which advisors or tools exist today; policy only governs already wired tools.
- No redesign of model-interaction recording beyond what is needed to keep debugging viable.

## Evidence / current constraints
- `AI::ContentGenerator#advisor_tools` is the source of truth for the base tool inventory. Today only Scribe receives tools.
- `AI::Adapters::RubyLLMToolAdapter` executes the underlying tool inside `execute`, rescues all exceptions, and JSON-serializes failures. In practice this swallows both app exceptions and `RubyLLM::Tool::Halt`, so approval cannot currently interrupt control flow.
- `AI::Client#chat` uses RubyLLM callbacks only for observation (`on_tool_call`, `on_tool_result`); those are too late to ask for permission.
- `GenerateAdvisorResponseJob` assumes a single uninterrupted run and currently treats unexpected interruption as an error.
- `Message` statuses are `pending|responding|complete|error|cancelled`. Adding approval can stay smaller if paused state is derived from related approval-request records rather than a new message enum.
- The conversation UI already has two fitting surfaces for this feature: the fixed header in [app/views/shared/_chat.html.erb](/root/p/small-council/app/views/shared/_chat.html.erb) and the per-message partial in [app/views/messages/_message.html.erb](/root/p/small-council/app/views/messages/_message.html.erb).

## Architecture summary

### Recommended boundary
Build this as an app-owned approval domain with a narrow AI integration seam:

1. Base tool inventory remains in `AI::ContentGenerator#advisor_tools`.
2. New app models persist tool policy and exact approval requests.
3. New app services resolve effective policy and apply user decisions.
4. The RubyLLM adapter enforces execution-time policy and raises an app-specific pause signal for approval-required calls.
5. `GenerateAdvisorResponseJob` catches that pause signal, leaves the message resumable, and exits cleanly.
6. User actions resolve the request and enqueue the same job again.

This keeps RubyLLM as the execution engine only. Approval state, permission semantics, UI, and pause/resume belong to the app.

### New app-owned components
- `ConversationToolPolicy` model: durable conversation policy.
- `ToolApprovalRequest` model: exact-call checkpoint ledger.
- `ToolApproval::PolicyResolver` service: resolves effective state for one conversation/advisor/tool.
- `ToolApproval::ExecutionGate` service: decides `allow`, `deny_in_flow`, or `approval_required` for one attempted call.
- `ToolApproval::DecisionApplier` service: maps the six user actions to request resolution plus policy upserts.
- `AI::ToolApprovalRequired` exception: app-owned pause signal carrying request/message/advisor/tool context.

### Files/modules affected
- AI seam:
   - [app/libs/ai/content_generator.rb](/root/p/small-council/app/libs/ai/content_generator.rb)
   - [app/libs/ai/client.rb](/root/p/small-council/app/libs/ai/client.rb)
   - [app/libs/ai/adapters/ruby_llm_tool_adapter.rb](/root/p/small-council/app/libs/ai/adapters/ruby_llm_tool_adapter.rb)
- Job flow:
   - [app/jobs/generate_advisor_response_job.rb](/root/p/small-council/app/jobs/generate_advisor_response_job.rb)
- Conversation/message UI and endpoints:
   - [app/controllers/messages_controller.rb](/root/p/small-council/app/controllers/messages_controller.rb)
   - [app/views/shared/_chat.html.erb](/root/p/small-council/app/views/shared/_chat.html.erb)
   - [app/views/messages/_message.html.erb](/root/p/small-council/app/views/messages/_message.html.erb)
   - [config/routes.rb](/root/p/small-council/config/routes.rb)
- New domain files:
   - models, migrations, controllers, service objects, and tests for policy + approval requests

## Data model

### `ConversationToolPolicy`
Purpose: durable configuration for one conversation, one tool, and either one advisor or all advisors.

Recommended fields:
- `account_id`
- `conversation_id`
- `advisor_id` nullable; `NULL` means all advisors in the conversation
- `tool_name`
- `state` enum: `not_available`, `ask`, `allowed`
- `updated_by_user_id`
- timestamps

Recommended constraints:
- tenant validation tying account, conversation, and advisor together
- validation that advisor belongs to the conversation when present
- unique index using PostgreSQL null-safe uniqueness for `conversation_id + advisor_id + tool_name`
   - implementation note: use an expression index such as `COALESCE(advisor_id, 0)` or equivalent, because a plain unique index will not prevent duplicate `NULL advisor_id` rows

Precedence:
1. advisor-specific row
2. all-advisors row
3. implicit default for tools already wired to that advisor: `ask`
4. tool not in the base inventory: unavailable regardless of policy rows

### `ToolApprovalRequest`
Purpose: checkpoint for one exact tool call attempt tied to one advisor response message.

Recommended fields:
- `account_id`
- `conversation_id`
- `message_id`
- `advisor_id`
- `tool_name`
- `arguments_json` JSONB
- `arguments_digest`
- `status` enum: `pending`, `approved`, `skipped`, `consumed`, `expired`
- `resolution_kind` enum nullable until resolved:
   - `allow_once`
   - `skip_once`
   - `allow_for_advisor`
   - `allow_for_all_advisors`
   - `deny_for_advisor`
   - `deny_for_all_advisors`
- `resolved_by_user_id`
- `resolved_at`
- `consumed_at`
- timestamps

Recommended constraints:
- unique partial index for one open request per exact call attempt:
   - `message_id + advisor_id + tool_name + arguments_digest` where `status = 'pending'`
- validations tying the request back to the same account and conversation as the message

Why keep two tables:
- `ConversationToolPolicy` answers “what is the conversation’s standing rule?”
- `ToolApprovalRequest` answers “what happened for this exact call attempt?”
- This separation avoids overloading policy rows with transient execution state.

## Execution flow and control-flow decisions

### 1. Before the LLM call
`AI::ContentGenerator#advisor_tools` should continue to produce the base inventory for the advisor. A new resolver layer then derives the advertised tool list for this run:

- `not_available`: do not advertise the tool to RubyLLM
- `ask`: advertise the tool
- `allowed`: advertise the tool

This pre-filter improves model behavior, but it is not the final authority.

### 2. At tool execution time
`AI::Adapters::RubyLLMToolAdapter` becomes the hard enforcement seam. For each tool call:

1. Normalize arguments and compute `arguments_digest`.
2. Ask `ToolApproval::ExecutionGate` for the outcome.
3. Handle outcomes as follows:
    - `allow`: execute the underlying tool and return the real tool result.
    - `deny_in_flow`: do not execute the underlying tool; return a structured denial payload so RubyLLM can continue the same turn.
    - `approval_required`: create or reuse a pending `ToolApprovalRequest`, then raise `AI::ToolApprovalRequired`.

### 3. Required adapter change
The current adapter is incompatible with approval because it rescues every exception and converts it to JSON. The implementation must change that control flow explicitly:

- allow `AI::ToolApprovalRequired` to bubble unchanged
- allow `RubyLLM::Tool::Halt` to bubble unchanged
- only convert genuine tool execution failures into error JSON

Recommended adapter rescue shape:

```ruby
rescue AI::ToolApprovalRequired, RubyLLM::Tool::Halt
   raise
rescue StandardError => error
   # log and return structured tool failure JSON
end
```

This is the key tightening versus the older plan. Approval pause is app-owned and must not be hidden inside a fake tool result.

### 4. Client behavior
`AI::Client` should remain on stock RubyLLM. The app-specific exception should pass through `with_retry` and `chat` unchanged.

- Do not wrap `AI::ToolApprovalRequired` as `APIError`.
- Do not retry `AI::ToolApprovalRequired`.
- Keep existing RubyLLM error handling for provider/API failures.

### 5. Job pause/resume behavior
`GenerateAdvisorResponseJob` must add a dedicated rescue branch for `AI::ToolApprovalRequired`.

Pause path:
- message remains `responding`
- pending `ToolApprovalRequest` is the source of truth that the message is awaiting approval
- broadcast the message frame so the inline approval card replaces the loading-only state
- exit the job without marking the message `error`

Resume path:
- a user action resolves the request and enqueues `GenerateAdvisorResponseJob` again for the same `advisor_id`, `conversation_id`, and `message_id`
- on rerun, the adapter consults the resolved request first:
   - exact approved request: execute once, then mark `consumed`
   - exact skipped request: return structured denial payload once, then mark `consumed`
   - different tool or different normalized arguments: evaluate policy again and create a new request if effective state is still `ask`

This satisfies the core product requirement:
- deny/forbidden remains in-flow
- approval-required pauses in the app and resumes via later job rerun

### 6. Structured denial payload
Denied or skipped calls should not raise. They should return structured JSON such as:

```json
{
   "ok": false,
   "error_code": "tool_not_available",
   "tool": "browse_web",
   "message": "This tool call was not allowed in this conversation.",
   "retryable": false
}
```

That lets RubyLLM continue the same completion loop and gives the model a stable signal to recover, explain, or choose another tool.

## UI surfaces

### Conversation header: proactive tool access
Add a `Tool access` control in the existing header in [app/views/shared/_chat.html.erb](/root/p/small-council/app/views/shared/_chat.html.erb).

Requirements:
- editable at any point during the conversation
- lists only tools already wired for the current conversation’s advisors
- supports these scopes:
   - one advisor + one tool
   - all advisors + one tool
- supports these states directly:
   - `Ask`
   - `Allowed`
   - `Not available`

Implementation direction:
- use a modal, drawer, or dropdown attached to the header; do not add a new page
- use Turbo forms so changes update the header and any visible paused cards without a full reload

### Message card: inline approval request
When a message is `responding` and has a pending approval request, [app/views/messages/_message.html.erb](/root/p/small-council/app/views/messages/_message.html.erb) should render a distinct approval card instead of showing only a spinner.

Card contents:
- advisor name
- tool display name
- concise argument summary
- brief explanation that the advisor paused waiting for approval
- six explicit actions matching the established requirements

Action labels:
1. Allow this tool call
2. Skip this tool call
3. Allow this tool call and allow this tool in this conversation for this advisor
4. Allow this tool call and allow this tool in this conversation for all advisors
5. Deny this tool in this conversation for this advisor
6. Deny this tool in this conversation for all advisors

UX notes from the overlay:
- keep labels explicit instead of collapsing meaning into shorthand
- make the paused state visually distinct from ordinary generation latency
- preserve keyboard and screen-reader clarity on buttons and form labels

## Controller / route shape
- Keep endpoints nested under conversations for authorization and tenant clarity.
- Add a controller for proactive policy updates, for example `ConversationToolPoliciesController`.
- Add a controller for pending-request resolution, for example `ToolApprovalRequestsController`.
- Return Turbo Stream responses so the message frame and header controls refresh in place.

Suggested route direction:
- nested under `resources :conversations`
- policy endpoint for create/update or single upsert
- request-resolution endpoint on a specific approval request

Exact route naming can be decided during implementation, but the plan should stay nested and conversation-scoped.

## Phased implementation steps

### Phase 1. Domain and persistence
1. Add `ConversationToolPolicy` migration, model, validations, enum, and null-safe uniqueness.
2. Add `ToolApprovalRequest` migration, model, validations, enums, associations, and exact-call uniqueness.
3. Add message associations/helpers needed to ask `awaiting_tool_approval?` and fetch the latest pending request.

### Phase 2. Policy resolution and decision application
1. Implement `ToolApproval::PolicyResolver` with precedence rules.
2. Implement `ToolApproval::DecisionApplier` to map the six UI actions to request resolution and policy upserts.
3. Define canonical argument normalization and digesting in one shared place.

### Phase 3. AI enforcement seam
1. Update `AI::ContentGenerator#advisor_tools` usage so the base inventory is filtered through the resolver before registering tools.
2. Add `ToolApproval::ExecutionGate` and call it from `AI::Adapters::RubyLLMToolAdapter`.
3. Introduce `AI::ToolApprovalRequired` and change adapter rescue behavior so pause signals propagate.
4. Ensure `AI::Client` does not retry or wrap approval-required exceptions.

### Phase 4. Job pause/resume
1. Add dedicated rescue handling in `GenerateAdvisorResponseJob` for `AI::ToolApprovalRequired`.
2. Broadcast the paused message state without marking the message complete or errored.
3. Add request-resolution flow that enqueues the same job again after user action.
4. Ensure exact approved/skipped requests are consumed once on rerun.

### Phase 5. UI and endpoints
1. Add conversation-header tool access controls.
2. Add inline approval card rendering in the message partial.
3. Add Turbo endpoints for policy updates and request resolution.
4. Handle empty and edge states cleanly:
    - no tools available for this conversation
    - request was already resolved elsewhere
    - request expired or message is no longer resumable

### Phase 6. Observability and cleanup
1. Log policy resolution, request creation, request resolution, and request consumption with conversation/message/advisor/tool identifiers.
2. Keep `ModelInteraction` unchanged for v1 except for confirming that denial payloads still record as tool results.
3. Update docs and curated memory after the behavior is implemented and verified.

## Risks / open questions
- Re-running the model after approval or skip can produce a different tool call. Mitigation: approvals are exact-match and one-time; new calls re-enter policy resolution.
- Argument normalization must be canonical or request matching will be noisy. Mitigation: centralize normalization and digest generation.
- Conversation-wide `allowed` must not expand the base inventory. Mitigation: policy can only affect tools already wired for that advisor class.
- Proactive policy changes can race with an already pending request. Recommendation: do not mutate existing resolved requests; apply new policy to future decisions, and let the current pending card still resolve explicitly.
- A long-lived pending request may become stale if the conversation changes materially. Recommendation: include `expired` status, but defer automatic expiry rules unless user testing shows a real need.

## Verification plan
Planned implementation verification:

1. Model tests
    - `bin/rails test test/models/conversation_tool_policy_test.rb`
    - `bin/rails test test/models/tool_approval_request_test.rb`
2. AI unit tests
    - `bin/rails test test/ai/unit/ruby_llm_tool_adapter_test.rb`
    - `bin/rails test test/ai/unit/client_test.rb`
3. Job tests
    - `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
4. Controller tests
    - `bin/rails test test/controllers/conversation_tool_policies_controller_test.rb`
    - `bin/rails test test/controllers/tool_approval_requests_controller_test.rb`
5. Integration flow
    - `bin/rails test test/integration/tool_approval_flow_test.rb`

Acceptance scenarios to cover:
1. Advisor-specific policy overrides all-advisors policy.
2. `not_available` removes the tool from the advertised list and still blocks it at execution time.
3. `allowed` executes without prompting.
4. `ask` creates one pending request and pauses the job.
5. Each of the six actions resolves correctly and resumes the job.
6. Skip/deny returns an in-flow denial payload and the advisor can still complete the turn.
7. Resume with changed arguments creates a new request instead of reusing the old one.

For this planning revision, no tests or commands were run. Investigation was read-only.

## Doc impact
- updated now: this plan artifact
- updated now: `.ai/MEMORY.md` with the adapter control-flow constraint
- implementation should update:
   - `.ai/docs/patterns/tool-system.md`
   - `.ai/docs/features/ai-integration.md`
   - `.ai/docs/features/model-interactions.md` only if approval-request or denial behavior becomes part of the debugging story

## Final recommendation
- Build tool approval entirely in the app, not in a RubyLLM fork.
- Use two explicit persistence layers: `ConversationToolPolicy` for durable configuration and `ToolApprovalRequest` for exact-call checkpoints.
- Filter tools before registration for better model behavior, but enforce again in `AI::Adapters::RubyLLMToolAdapter`.
- Treat denied calls as structured in-flow tool results.
- Treat approval-required calls as an app-owned pause by raising `AI::ToolApprovalRequired`, catching it in `GenerateAdvisorResponseJob`, and resuming later by re-enqueueing the same job.

Approve this plan?