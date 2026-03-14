# Plan: Small Council conversation-context handling rethink

Date: 2026-03-12

## Goal
- Revise the conversation-context approach into a concrete, simple plan that keeps prompts smaller and more relevant while preserving enough state for long-running conversations.

## Non-goals
- Implement product code.
- Reintroduce a broad `ConversationContextBuilder` / `ConversationStateUpdater` architecture.
- Design a general long-term memory system or new user-facing summary UX.
- Keep historical tool call results in future prompts.

## Scope + assumptions
- In scope: prompt context composition, compaction trigger policy, post-compaction message filtering, and an implementation plan for a later `change` workflow.
- Out of scope: schema redesign, provider benchmarking, UI changes, and tool-policy expansion beyond prompt inclusion/exclusion.
- Read-only planning only: yes.
- Assumption: the evidence collected in the original investigation still stands, especially around `RespondTask`, runtime types, stored `ModelInteraction` data, and existing historical tool-result replay behavior.
- User-approved decisions incorporated here are authoritative for this revision.

## Evidence basis
- Canonical planning instructions: `.ai/agents/planner.md`, `.ai/RULES.md`, `.ai/docs/overview.md`, `.ai/templates/plan.template.md`
- Existing investigation and plan evidence retained from:
  - `.ai/plans/2026-03-12-01-conversation-context-rethink.md` (prior version)
  - `app/libs/ai/tasks/respond_task.rb`
  - `app/libs/ai/runtimes/open_conversation_runtime.rb`
  - `app/libs/ai/runtimes/consensus_conversation_runtime.rb`
  - `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb`
  - `app/libs/ai/trackers/model_interaction_tracker.rb`
  - `app/libs/ai/agents/advisor_agent.rb`

## Revised recommendation
- Use a **simple hybrid design**:
  1. Keep prompt assembly centered in `RespondTask`.
  2. Stop resending historical tool call results in prompts.
  3. Add explicit conversation compaction as a separate task/state transition.
  4. After compaction, prompt context should contain:
     - the **latest compacted summary/state**, and
     - **newer messages since compaction**, filtered by simple role-aware rules.
- Compaction should be **triggered by conversation type**:
  - `open`: only by size/history pressure.
  - `consensus` and `brainstorming`: by round boundaries **and** by size/history pressure.
- Keep the design intentionally legible: one current compacted state per conversation, one compaction boundary, and simple filtering defaults for newer messages.

## Simple compaction trigger matrix

| Conversation type | Round-boundary trigger | Size/history-pressure trigger | Recommended behavior |
|---|---|---|---|
| `open` | No | Yes | Compact only when recent history grows too large or too deep |
| `consensus` | Yes | Yes | Prefer compaction at natural round boundaries; also compact earlier if pressure is high |
| `brainstorming` | Yes | Yes | Same as consensus: use rounds as clean cut points, but do not wait if prompt pressure is already too high |

### Recommended trigger defaults
- Treat compaction as eligible when either of these pressure signals is hit:
  - selected prompt context would exceed the configured size budget, or
  - the number of post-compaction messages exceeds a simple history-depth threshold.
- For `consensus` / `brainstorming`, if a round just completed and there are meaningful new decisions/proposals, compact there even if size pressure is only moderate.
- Avoid overly frequent compaction: prefer one compaction at a clear boundary over repeated tiny compactions.

## What goes into prompt context after compaction

### Always include
- advisor system prompt
- any runtime-specific prompt/instructions
- the **latest compacted summary/state** for the conversation
- filtered **newer messages since the compaction boundary**
- the current message being answered

### The compacted summary/state should contain
- stable conversation purpose / topic
- active constraints or instructions still in force
- accepted decisions / commitments
- unresolved questions or active branches
- relevant participant state needed for the next turn
- for round-based modes, a short round-status snapshot if still relevant

### Newer messages since compaction should be
- included as raw messages, not re-summarized inline
- filtered by advisor role and relevance defaults
- bounded by a simple size/history budget even after compaction

## Filtering rules for newer messages since compaction

### Recommended defaults for scribe
- Include all user messages since compaction.
- Include all scribe messages since compaction.
- Include advisor messages that materially affect coordination, synthesis, decisions, or round progression.
- Include direct mentions and `@all` messages.
- Exclude duplicate placeholder/error noise unless needed for the current turn.
- Do **not** include historical tool call results; only keep any durable outcome if it has already been expressed in message text or compacted state.

### Recommended defaults for non-scribe advisors
- Include the current message being answered.
- Include recent user messages since compaction that define the current ask.
- Include recent scribe messages since compaction.
- Include the advisor's own messages since compaction.
- Include another advisor's message only if one of these is true:
  - it directly mentions the responding advisor,
  - it uses `@all`,
  - it is part of the same active reply branch, or
  - it contains a decision/constraint that the scribe did not already carry forward.
- Exclude unrelated cross-advisor discussion by default.
- Do **not** include historical tool call results.

### Simplicity rule
- Prefer understandable inclusion rules over inferred semantic relevance.
- If a rule would require heavy scoring, embeddings, or opaque heuristics, it is out of scope for this plan.

## What remains explicitly out of prompt context
- historical tool call results from prior turns
- raw pre-compaction message history older than the current compaction boundary
- irrelevant advisor-to-advisor exchanges for the current responder
- duplicate replay of information already preserved in the compacted summary/state
- internal tracker/audit records unless deliberately converted into user-visible message content

## Phased implementation plan for a future `change` workflow

1. **Remove historical tool-result replay from prompt assembly**
   - Stop sending prior `tool_result` payloads as prompt context.
   - Keep stored tool traces only for audit/debug and tracker visibility.

2. **Introduce minimal compaction state**
   - Add a single conversation-level compacted summary/state and a clear boundary indicating what history it replaces.
   - Keep storage and access simple; avoid a generalized context-subsystem abstraction.

3. **Add compaction task and trigger checks**
   - Implement an explicit `CompactConversationTask` (name can vary, behavior should not).
   - Add trigger evaluation based on conversation type:
     - `open`: size/history pressure only
     - `consensus` / `brainstorming`: round boundary and size/history pressure

4. **Update prompt assembly to use compacted state + filtered newer messages**
   - In `RespondTask`, build context from:
     - system/runtime prompt
     - latest compacted summary/state
     - filtered post-compaction messages
     - current message
   - Apply separate default filters for scribe vs non-scribe.

5. **Add lightweight observability**
   - Reuse `ModelInteraction` / usage data to confirm prompt sizes drop and stay bounded.
   - Log or flag when compaction should have happened but did not, or when post-compaction prompts still exceed budget.

6. **Document the rules**
   - Update AI/conversation docs with:
     - trigger matrix by conversation type
     - post-compaction prompt composition
     - filtering defaults
     - explicit exclusion of historical tool call results

## Acceptance criteria
- Historical tool call results are no longer resent in advisor prompts.
- Prompt assembly can operate from one latest compacted summary/state plus newer filtered messages.
- Compaction trigger behavior differs by conversation type exactly as approved:
  - `open`: size/history pressure
  - `consensus` / `brainstorming`: round boundary plus size/history pressure
- Scribe and non-scribe use distinct, documented default filtering rules for newer messages.
- Raw messages older than the compaction boundary are excluded from prompt context unless re-expressed in compacted state.
- The implementation plan is localized and does not require reviving a broad context-builder/state-updater architecture.
- Follow-on docs to explain the new behavior are identified.

## Risks / open questions
- **Summary fidelity risk:** compacted state may omit nuance that later matters.
- **Boundary quality risk:** for round-based modes, the app needs a reliable notion of when a round is complete enough to compact.
- **Decision duplication risk:** the same constraint may appear in both compacted state and newer messages unless deduping is kept simple.
- **Threshold tuning:** initial size/history thresholds will likely need one tuning pass after rollout.
- **State shape question:** the exact storage format for compacted summary/state should stay minimal, but still needs one implementation decision.
- **Fallback behavior:** if compaction fails or produces low-confidence output, the system needs a safe default path.

## Verification
- Review targeted tests around `RespondTask`, runtimes, and trackers.
- Add tests for trigger policy by conversation type.
- Add tests that confirm prompt composition after compaction includes:
  - compacted summary/state
  - filtered newer messages
  - no historical tool-result replay
- Inspect a few `ModelInteraction.request_payload` examples after implementation to confirm the prompt contents match the rules above.
- Compare before/after prompt-size distribution using existing usage/model-interaction data.

## Doc impact
- doc impact: deferred
- Follow-on `change` should update:
  - `.ai/docs/features/ai-integration.md`
  - `.ai/docs/features/conversation-system.md`
  - `.ai/docs/patterns/prompts.md`

## Rollback (if applicable)
- Disable compaction-based prompt assembly and return to simpler recent-history selection if needed.
- Because the plan keeps changes localized to prompt composition and compacted-state handling, rollback should not require a broader architecture rollback.

## Closeout
- Recommendation: adopt explicit compaction plus filtered post-compaction context, with triggers varying by conversation type and with historical tool results excluded from prompts.
- Unknowns remaining: exact compacted-state storage shape, initial thresholds, and the precise round-complete signal for round-based modes.

Approve this plan?
