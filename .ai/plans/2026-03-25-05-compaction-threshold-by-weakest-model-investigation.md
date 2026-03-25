# Investigation: Dynamic Compaction Threshold From Weakest Involved Model

1) Intent
- Question to answer: How should compaction threshold be computed from context limits of the currently involved models, using the weakest model as the cap?
- Success criteria: Propose a concrete threshold algorithm, identify code insertion points, and define a low-risk rollout path.

2) Scope + constraints
- In-scope:
  - Current compaction trigger logic and data available for model limits.
  - Runtime points where involved advisors/models can be derived.
  - Practical estimation strategy for prompt size.
- Out-of-scope:
  - Implementing code changes in this investigation.
  - Retrofitting tokenizer-accurate counting for every provider.
- Read-only investigation: yes
- Timebox: short focused pass

3) Evidence collected
- Trigger today is fixed, char-based:
  - app/libs/ai/runtimes/conversation_runtime.rb
  - COMPACTION_THRESHOLD = 25_000
  - compaction_required? compares joined content length since last compaction.
- Compaction prompt scope:
  - app/libs/ai/prompts/agents/conversation_compactor.erb
  - Uses conversation.messages.since_last_compaction for source text.
- Model limit data exists:
  - app/models/llm_model.rb and db/schema.rb (context_window column)
  - app/libs/ai/model_manager.rb stores context_window from provider metadata.
- Effective model resolution exists per advisor:
  - app/models/advisor.rb effective_llm_model
- Runtime context uses selected advisor model:
  - app/libs/ai/contexts/conversation_context.rb model
  - app/libs/ai/tasks/base_task.rb runs chat with context.model
- Tests already cover compaction behavior at runtime boundary:
  - test/libs/ai/runtimes/conversation_runtime_test.rb

4) Findings
- Current compaction trigger is not model-aware and uses character count, not token budget.
- The repository already stores model context limits in llm_models.context_window, which is sufficient for a weakest-model threshold.
- The strongest safe interpretation of currently involved models is conversation participant advisors that can produce/consume turns in this conversation, including scribe.
- Token-accurate thresholding is not directly available for pre-flight message content; an estimator is required.

5) Proposed threshold model
- Define involved advisors for thresholding:
  - Default: conversation.all_participant_advisors (includes scribe).
  - Optional refinement later: runtime-specific next responders plus scribe.
- Resolve involved models:
  - advisor.effective_llm_model for each involved advisor.
- Weakest window:
  - weakest_ctx = minimum(context_window) across resolved models.
  - If any involved model has missing context_window, use conservative fallback window.
- Budget split (token space):
  - prompt_budget = weakest_ctx * 0.70
  - reserve_output = weakest_ctx * 0.20
  - safety_margin = weakest_ctx * 0.10
  - trigger_limit = prompt_budget (equivalently weakest_ctx - reserve_output - safety_margin)
- Estimated prompt tokens:
  - estimated_tokens = static_overhead_tokens + estimated_history_tokens
  - estimated_history_tokens = chars_since_last_compaction / chars_per_token_estimate
  - chars_per_token_estimate default: 4.0
- Trigger rule:
  - compaction_required? when estimated_tokens >= trigger_limit

6) Why weakest-model is correct here
- A conversation can route turns to different advisors with different models.
- Context should stay under the smallest active context window to avoid failure on the weakest participant path.
- Using weakest model creates predictable behavior and avoids model-specific surprise failures.

7) Practical defaults and fallback policy
- Missing context_window fallback:
  - conservative_default_ctx = 8_192 tokens.
- Missing model fallback:
  - if no involved models resolve, retain current hard fallback threshold behavior.
- Estimation fallback:
  - if chars_per_token estimate unavailable, use 4.0 chars/token.

8) Recommended implementation points
- Add a small calculator/service, for example:
  - app/libs/ai/services/compaction_threshold_calculator.rb
- Replace fixed check in:
  - app/libs/ai/runtimes/conversation_runtime.rb compaction_required?
- Reuse existing model resolution:
  - app/models/advisor.rb effective_llm_model
  - app/models/conversation.rb all_participant_advisors

9) Validation plan
- Unit tests for calculator:
  - weakest model selection
  - missing context_window fallback
  - budget math
- Runtime tests update:
  - test/libs/ai/runtimes/conversation_runtime_test.rb
  - assert compaction_required? with modeled limits instead of static 25_000 chars.
- Optional runtime observability:
  - log weakest_ctx, estimated_tokens, trigger_limit when evaluating compaction.

10) Options considered
- Option A: Keep fixed char threshold
  - Simple but not model-safe.
- Option B: Weakest-model dynamic threshold with token estimation
  - Recommended: practical, low-risk, aligns with current data model.
- Option C: Exact tokenizer counting per provider/model
  - Most accurate, highest complexity and maintenance burden.

11) Recommendation
- Adopt Option B now.
- Implement weakest-model dynamic threshold with conservative defaults and simple token estimation.
- Keep estimator and constants centralized so tuning is easy without runtime rewrites.

12) Handoff
- Next workflow: change
- Proposed scope:
  - introduce threshold calculator service
  - refactor compaction_required? to use service
  - add tests for calculator and runtime
- Verification commands:
  - bin/rails test test/libs/ai/runtimes/conversation_runtime_test.rb
  - bin/rails test test/libs/ai/services/compaction_threshold_calculator_test.rb
  - bin/rails test
