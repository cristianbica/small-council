# Investigation: advisors overusing tools for in-thread follow-ups

1) **Intent**
- Question to answer: Why do advisors call memory/conversation tools excessively when the user asks about a previous message in the current conversation thread (example: conversation 36)?
- Success criteria: Identify concrete root causes with evidence and propose a minimal, high-confidence bug-fix scope.

2) **Scope + constraints**
- In-scope:
  - Tool-selection and context assembly for advisor responses
  - Runtime evidence from conversation 36 (`ModelInteraction` + messages)
  - Fix options and recommendation
- Out-of-scope:
  - Implementing code changes (deferred to `change` workflow)
  - Provider-level model reliability tuning
- Read-only default acknowledged: yes
- Instrumentation/spikes allowed (explicit permission): no
- Timebox: ~60 minutes

3) **Evidence collected**
- Files inspected:
  - `app/libs/ai/content_generator.rb`
  - `app/libs/ai/client.rb`
  - `app/libs/ai/context_builders/conversation_context_builder.rb`
  - `app/libs/ai/context_builders/base_context_builder.rb`
  - `app/libs/ai/model_interaction_recorder.rb`
  - `app/jobs/generate_advisor_response_job.rb`
  - `app/libs/ai/tools/internal/query_memories_tool.rb`
  - `app/libs/ai/tools/internal/query_conversations_tool.rb`
  - `app/libs/ai/tools/internal/read_conversation_tool.rb`
  - `app/models/message.rb`
- Commands run:
  - `bin/rails runner` queries against conversation 36 messages and `ModelInteraction` records
  - Tool-count and per-message sequence summaries
  - Runtime check of `AI::ContentGenerator#advisor_tools` for scribe vs non-scribe
- Observations:
  - Conversation 36 shows repeated tool loops before errors:
    - msg `430` (`technical-architect`): 14 tool calls
    - msg `432` (`technical-architect`): 10 tool calls
    - msg `437` (`scribe`): 25 tool calls
    - msg `443` (`game-design-lead`): 10 tool calls
  - Example sequence (msg `430`): `query_conversations -> query_memories -> query_conversations -> ... -> read_conversation -> read_memory x5 -> query_conversations`.
  - There is no explicit max-tool-call budget or loop guard in `AI::Client`.
  - In `AI::ContentGenerator#generate_advisor_response`, `parent_message` is passed in, but `build_conversation_messages_with_thread(conversation, parent_message)` does not use `parent_message` at all.
  - This means a reply to a specific message is not context-focused on that thread/parent; advisors see broad conversation context and can drift to tool search.
  - Non-scribe advisors currently receive memory/web tools (`query_memories`, `list_memories`, `read_memory`, `browse_web`), which are enough to create tool loops even without conversation search tools.

4) **Findings**
- How it works today:
  - Advisor response generation always exposes tools (non-scribe: memory+web; scribe: memory+conversation+write/admin).
  - Prompt context always includes conversation-wide message history; parent-thread focus is not enforced.
  - Client allows unbounded tool-call chains until model/provider stops.
- Root cause / repro:
  1. User asks follow-up about previous message in current thread.
  2. Model has no strong “answer-from-thread-first” guardrail and no parent-thread-focused prompt slice.
  3. Model chooses tools (often memory/conversation search) repeatedly.
  4. No tool budget halts runaway loops, leading to API/provider errors.
- Confidence level: high

5) **Options**
- Option A (prompt + context focus only):
  - Use `parent_message` to build focused thread context for replies (parent + sibling replies + concise thread summary), not full-history-only framing.
  - Add a system directive for advisors: “Answer from provided conversation thread first; call tools only if required info is missing from thread.”
  - Pros: minimal behavior change, likely biggest gain for this bug.
  - Cons: does not hard-stop worst-case tool loops.

- Option B (hard guard only):
  - Add max tool-call budget per response (e.g., 2 for non-scribe, 6 for scribe), with graceful fallback response when exceeded.
  - Pros: deterministic protection from runaway loops.
  - Cons: can still waste calls before hitting cap; does not directly improve thread relevance.

- Option C (recommended, combined):
  - Implement Option A + Option B together.
  - Add dynamic tool policy for non-scribe follow-up replies:
    - If `parent_message` present and thread contains needed context, disable tools for first attempt.
    - Optional fallback: retry once with tools enabled only if first response is empty/error.
  - Pros: best precision + safety; directly addresses symptom and failure mode.
  - Cons: slightly larger but still scoped change.

**Recommendation + rationale:**
- Choose **Option C** with minimal first increment:
  1. Make `parent_message` actually shape prompt/context.
  2. Add explicit “thread-first, tool-second” instruction for advisor replies.
  3. Add non-scribe tool budget cap.
- This targets the root cause (unfocused context + weak policy) and adds a safety brake (budget cap).

6) **Handoff**
- Next workflow: `change` (`bug`)
- Proposed scope:
  1. `AI::ContentGenerator`: implement parent-thread-focused message building and/or context injection.
  2. `AI::Client`: add configurable per-call max tool interactions (default safe value; stricter for non-scribe).
  3. `AI::ContentGenerator#build_client` / `generate_advisor_response`: pass tool-policy knobs by role + reply type.
  4. Add/adjust unit tests around message building and tool-budget behavior.
- Verification plan:
  - Unit tests for thread-focused message assembly when `parent_message` is present.
  - Unit tests for tool budget enforcement and graceful stop behavior.
  - Manual replay smoke test on conversation-like scenario (mention follow-up to previous message) and confirm tool calls reduced.

7) **Open questions**
- Should `browse_web` ever be available for non-scribe in normal conversation replies, or only behind explicit user request?
- For scribe, should write/admin tools be disabled by default unless user intent is clearly mutative?
- Should the budget cap be global, per role, or per RoE mode?
