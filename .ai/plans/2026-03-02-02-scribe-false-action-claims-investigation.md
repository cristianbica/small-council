# Investigation Report: Scribe claims action success without durable side effects

1) **Intent**
- **Question to answer:** Why does Scribe sometimes claim it completed a new action (especially similar to prior actions) when it did not, and what strategies should we adopt?
- **Success criteria:** Evidence-backed root cause analysis, feature map, concrete options with tradeoffs, and a tight next-step scope for `change` workflow.

2) **Scope + constraints**
- **In-scope:** Conversation/tool orchestration, context construction, Scribe behavior, model interaction traces, and DB side effects for conversation `21`.
- **Out-of-scope:** Product code changes or migrations.
- **Read-only default acknowledged:** yes
- **Instrumentation/spikes allowed (explicit permission):** no (not used)
- **Timebox:** no explicit limit (used targeted read-only inspection)

3) **Evidence collected**
- **Docs inspected (docs-first):**
  - `.ai/docs/overview.md`
  - `.ai/docs/features/conversation-system.md` (path used because `.ai/docs/conversation-system.md` not present)
  - `.ai/docs/features/model-interactions.md` (path used because `.ai/docs/model-interactions.md` not present)
  - `.ai/docs/features/ai-integration.md` (path used because `.ai/docs/ai-integration.md` not present)
  - `.ai/docs/patterns/tool-system.md`
- **Key code inspected:**
  - `app/libs/ai/content_generator.rb`
  - `app/libs/ai/client.rb`
  - `app/libs/ai/model_interaction_recorder.rb`
  - `app/libs/ai/context_builders/base_context_builder.rb`
  - `app/libs/ai/context_builders/conversation_context_builder.rb`
  - `app/libs/ai/adapters/ruby_llm_tool_adapter.rb`
  - `app/libs/ai/tools/**/*` (write tools + ask tool)
  - `app/jobs/generate_advisor_response_job.rb`
  - `app/services/conversation_lifecycle.rb`
  - `app/models/space.rb`, `app/models/conversation.rb`, `app/models/message.rb`, `app/views/messages/_message.html.erb`
- **Commands run (read-only):**
  - `bin/rails runner` query for conversation 21 timeline/messages/interactions
  - `bin/rails runner` query for model_interactions (tool vs chat correlation)
  - `bin/rails runner` query for persisted side effects in space 2 (councils/advisors/memories)
  - `bin/rails runner` query for context growth (`request_payload.messages` counts)
  - `bin/rails runner` query for payload tails in messages 137/139/143
- **Key observations:**
  - In conversation 21, multiple Scribe responses claim success while **no tool call happened**:
    - message IDs `127`, `129`, `137`, `139`, `141`, `143` have `interactions: 1` and that one is `chat` only.
  - For message IDs `137/139/143`, request payload tails include prior assistant text like “Created successfully…”, and the model repeats this pattern without new tool execution.
  - Context size increases turn-by-turn (message count in request payload grew to 29 by message 158; token input similarly grows).
  - `AI::ContentGenerator#build_conversation_messages_with_thread` passes the full conversation thread; there is no recency/action-ledger separation.
  - There is no strict “action requires tool evidence” policy in Scribe prompt (`Space#create_scribe_advisor` prompt).
  - Tool executions are recorded but only as interaction traces; there is no runtime gate that blocks assistant claiming success if no corresponding tool result exists.
  - Additional reliability finding: `ask_advisor` tool returns success but enqueues `GenerateAdvisorResponseJob` with a non-pending message; job exits early due to `unless message.pending?`.

4) **Findings**
- **How it works today (feature map):**
  1. User message -> `ConversationLifecycle#user_posted_message` -> placeholder + `GenerateAdvisorResponseJob`.
  2. Job calls `AI::ContentGenerator#generate_advisor_response`.
  3. Generator builds context via `ConversationContextBuilder` and messages via full-thread builder.
  4. `AI::Client` attaches tools and executes chat; `ModelInteractionRecorder` captures chat/tool events.
  5. Final assistant text is persisted as message content regardless of whether any tool executed.
- **Probable root cause / repro:**
  - **Primary:** Full-history conversational context includes previous “Created successfully” assistant outputs; model pattern-matches and emits another success narrative without calling tools.
  - **Contributing:** No orchestration contract requiring tool evidence before success claims.
  - **Contributing:** No “action ledger” or last-known state summary to disambiguate “done previously” vs “done now”.
  - **Secondary bug:** `ask_advisor` success semantics are inconsistent with job contract (non-pending message), creating false-positive “done” outcomes.
- **Confidence:**
  - Primary root cause: **high** (direct evidence in conversation 21 model interaction payloads)
  - Secondary orchestration issues: **high**
  - Contribution of provider/model quirks: **medium**

5) **Options (A/B/C)**
- **Option A — Prompt/policy hardening (fastest):**
  - Add strict Scribe policy: never say created/updated/assigned unless current turn includes successful tool result; otherwise state “not executed yet” and call tool or ask permission.
  - Require response footer schema (internal) like `action_status: executed|not_executed` + `evidence: [tool_name, id]`.
  - **Pros:** low implementation cost, immediate reduction of hallucinated completion.
  - **Cons:** prompt-only controls are probabilistic; can regress under long contexts.

- **Option B — Tool protocol + orchestrator guarantees (recommended):**
  - Enforce deterministic tool-call protocol:
    - per-turn function-call IDs,
    - strict JSON args validation,
    - mandatory tool result attachment for side-effect claims.
  - Add server-side post-check before persisting assistant message: if message contains action-claim verbs (created/updated/assigned/deleted/finished), require matching successful tool interaction in same turn; otherwise rewrite/append warning state.
  - Fix `ask_advisor` flow to align with pending-message contract (or adapt job contract accordingly).
  - **Pros:** moves from “best effort” to enforceable guarantees; addresses root cause and known protocol mismatch.
  - **Cons:** moderate scope; requires careful UX wording for blocked claims.

- **Option C — State architecture change (most robust, larger):**
  - Split model context into:
    1) conversational narrative (recency window),
    2) action ledger (durable, structured tool outcomes),
    3) scratchpad/tool thoughts (not echoed as user-visible truth).
  - Two-phase commit pattern for side effects:
    - phase 1: plan/intend,
    - phase 2: execute tools + verify DB state,
    - then user-visible confirmation.
  - **Pros:** strongest reliability and auditability; aligns with mature agentic patterns.
  - **Cons:** highest complexity and refactor risk.

- **How others handle this (industry patterns):**
  - ReAct variants with explicit `Thought -> Act(tool) -> Observation` and “no final claim without Observation”.
  - Toolformer/function-calling with strict schemas + deterministic tool routing.
  - Two-phase commit for side effects in production copilots.
  - Deterministic tool acknowledgments (UI badges/receipts linked to tool call IDs).
  - Replayable traces with per-turn action assertions in eval harnesses.

6) **Recommendation + rationale**
- **Recommend Option B as the next step**, with a minimal first slice:
  1) enforce “claim requires same-turn successful tool_result” for write claims,
  2) add a compact action ledger to context,
  3) patch `ask_advisor` protocol mismatch.
- **Why:** This directly addresses observed failures in conversation 21, is materially more reliable than prompt-only, and is much smaller than a full architecture split.

7) **Handoff**
- **Next workflow:** `change` (bug)
- **Proposed scope (tight):**
  - Implement same-turn claim validator for write-action language on advisor responses.
  - Add action ledger context snippet (last N successful/failed tool actions) and include it in generation context.
  - Fix `AI::Tools::Conversations::AskAdvisorTool` + `GenerateAdvisorResponseJob` contract mismatch.
  - Add tests covering:
    - repeated “create memory” request where prior success text exists but no new tool call,
    - successful write claim with tool evidence,
    - ask_advisor execution path.
- **Verification plan:**
  - Unit tests for tool protocol guard + ledger builder.
  - Integration test around conversation turn replay reproducing message 137/139 pattern.
  - Manual check in conversation UI interactions modal: claimed action must show matching tool record in same turn.

8) **Open questions**
- Should user-visible responses include explicit operation receipts (e.g., `memory_id`, `council_id`) by default?
- For partial-failure turns (some tools succeeded, later parse error), should side effects be rolled back, or surfaced as partial-complete with compensating guidance?
- Should the claim validator be lexical (verb-based) or driven by structured response schema from the model?
