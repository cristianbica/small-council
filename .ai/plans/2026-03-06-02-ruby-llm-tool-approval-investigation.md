# Investigation: RubyLLM Tool Approval Model

Date: 2026-03-06

## 1. Intent

- Question to answer:
  - Can the new tool approval model be implemented primarily in RubyLLM, using concepts like `with_tool(... requires_approval:, allowed_arguments:)`, an `ask_approval` tool or schema-driven approval response, and execution-time permission checks that return a forbidden tool result and continue the same flow?
- Success criteria:
  - Validate the current RubyLLM and app behavior with evidence.
  - Distinguish what is possible with stock RubyLLM, with a gem extension/fork, and at the app layer without forking.
  - Recommend a practical handoff scope for a later `change` workflow.

## 2. Scope + constraints

- In scope:
  - Current Small Council AI tool flow.
  - RubyLLM tool declaration, serialization, and execution flow.
  - Feasibility of approval metadata, approval requests, and execution-time permission checks.
- Out of scope:
  - Product implementation.
  - Schema design for app persistence beyond what is needed to scope the follow-on change.
  - UI details beyond the architectural seam required for approval.
- Read-only default acknowledged: yes
- Instrumentation/spikes allowed: no
- Timebox: 60 minutes max

## 3. Evidence collected

- Files inspected:
  - `.ai/docs/overview.md`
  - `.ai/docs/patterns/tool-system.md`
  - `.ai/plans/2026-03-06-01-tools-approval.md`
  - `app/libs/ai/client.rb`
  - `app/libs/ai/adapters/ruby_llm_tool_adapter.rb`
  - `app/libs/ai/content_generator.rb`
  - `app/libs/ai/tools/base_tool.rb`
  - `app/jobs/generate_advisor_response_job.rb`
  - `app/models/message.rb`
  - `/root/.local/share/mise/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/gems/ruby_llm-1.13.2/lib/ruby_llm/chat.rb`
  - `/root/.local/share/mise/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/gems/ruby_llm-1.13.2/lib/ruby_llm/tool.rb`
  - `/root/.local/share/mise/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/gems/ruby_llm-1.13.2/lib/ruby_llm/tool_call.rb`
  - `/root/.local/share/mise/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/gems/ruby_llm-1.13.2/lib/ruby_llm/providers/openai/tools.rb`
  - `/root/.local/share/mise/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/gems/ruby_llm-1.13.2/lib/ruby_llm/providers/anthropic/tools.rb`
  - `/root/.local/share/mise/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/gems/ruby_llm-1.13.2/lib/ruby_llm/providers/gemini/tools.rb`
- Commands run:
  - None. Investigation was file inspection only.
- Key observations:
  - `RubyLLM::Chat#with_tool` and `#with_tools` register tool instances plus only `choice` and `calls` preferences.
  - `RubyLLM::Chat#complete` calls the provider, then if tool calls are returned it enters `handle_tool_calls`, executes each tool, appends tool-result messages, and recursively calls `complete` again.
  - `RubyLLM::Chat#execute_tool` checks only whether the tool exists, then calls `tool.call(args)`.
  - `RubyLLM::Tool` supports parameter/schema declarations plus `provider_params`, but no approval metadata.
  - Provider serializers deep-merge `tool.provider_params` into provider-specific tool declarations, but nothing indicates providers understand approval semantics.
  - Small Council already injects a prompt-level tool policy message in `AI::Client`, but that is advisory only.
  - `AI::Adapters::RubyLLMToolAdapter` rescues all exceptions from tool execution and serializes non-string results to JSON, which currently blocks both exception-based interruption and `RubyLLM::Tool::Halt` pass-through.
  - `GenerateAdvisorResponseJob` assumes one uninterrupted run and currently treats unexpected interruptions as errors.

## 4. Findings

### How the flow works today

1. `AI::ContentGenerator#advisor_tools` decides which app tools are available for the advisor. Today, only Scribe gets tools, including mutating tools.
2. `AI::Client#build_ruby_llm_chat` creates a `RubyLLM::Chat`, registers the tools through `chat.with_tools`, and wires model-interaction callbacks.
3. `AI::Client#chat` injects system messages for council context, memory index context, and a prompt-level tool policy, then adds the conversation messages and calls `chat.complete`.
4. In RubyLLM, `Chat#complete` sends the request to the provider. If the model responds with tool calls, `Chat#handle_tool_calls` runs.
5. `Chat#handle_tool_calls` emits `on_tool_call`, executes the tool via `execute_tool`, emits `on_tool_result`, appends the tool result as a tool message, and then recursively calls `complete` to continue the same model flow.
6. In Small Council, the actual tool logic runs inside the dynamically generated RubyLLM tool class from `AI::Adapters::RubyLLMToolAdapter`, which delegates to the app tool with context.

### Validation and refinement of the supplied findings

- Confirmed:
  - RubyLLM supports `with_tool` and `with_tools`, `tool_prefs`, `with_schema`, `on_tool_call`, and `on_tool_result`.
  - `handle_tool_calls` executes tool calls unconditionally from the RubyLLM point of view once the model has emitted them.
  - `RubyLLM::Tool` has params/schema and `provider_params`, but no native `requires_approval` or `allowed_arguments` concept.
  - Provider serializers merge `provider_params` into tool declarations only.
  - The app already relies on a prompt-level tool policy message.
- Refined:
  - RubyLLM does have a stop-the-loop concept, `RubyLLM::Tool::Halt`, but the current app adapter prevents using it because it serializes non-string tool results instead of letting `Tool::Halt` pass through.
  - The current app adapter also rescues all execution exceptions, so even if the app defined a custom approval exception today, it would be swallowed and returned as tool JSON rather than interrupting the run.
  - `with_schema` is not an approval mechanism. It shapes model output parsing/request format, but it does not add a pre-execution authorization step to the tool loop.

### Whether RubyLLM can support this without modification

Short answer: only partially.

What stock RubyLLM can support today:
- Tool availability filtering before the call starts.
- Execution-time permission checks inside the tool implementation or adapter that return a structured forbidden result.
- Continuing the same model flow after a forbidden result, because `handle_tool_calls` already appends the tool result and calls `complete` again.

What stock RubyLLM cannot support as a first-class feature today:
- A native API like `with_tool(... requires_approval:, allowed_arguments:)`.
- A generic pre-execution approval hook before `execute_tool` runs.
- Waiting for a human approval decision and then resuming the same in-process `complete` call.

Why:
- The only built-in tool metadata channels are schema and provider-specific params.
- The callbacks exposed by `Chat` are observational (`on_tool_call`, `on_tool_result`), not decision hooks.
- `handle_tool_calls` is synchronous and recursive. It can continue after a tool result, but it does not have a built-in pause/resume contract for external user interaction.

### Whether a gem extension or fork could support it cleanly

Yes, but only if the extension adds a real authorization seam in RubyLLM.

The cleanest gem-level design would add two concepts:

1. Tool metadata that RubyLLM understands locally, for example:
   - `requires_approval:`
   - `allowed_arguments:`
   - possibly `approval_policy:` or a callable permission object

2. A pre-execution authorization hook in `Chat`, for example:
   - `before_tool_execute`
   - `authorize_tool_call`
   - or a typed result from `execute_tool` such as `allow`, `forbid`, `approval_required`

With that seam, a fork or upstream extension could:
- check argument-level policy before calling the underlying tool
- return a structured forbidden tool result and continue the same model flow
- return a typed halt or exception for `approval_required`, so the host app can persist an approval request and stop the run cleanly

Limits even with a clean fork:
- RubyLLM still would not own the user interaction. The host app must still persist approval state, present the approval UI, and trigger the resume run later.
- Provider declarations still would not natively understand approval semantics, so this metadata would remain RubyLLM-local.

Conclusion:
- A gem extension/fork can support the DSL and the permission seam cleanly.
- It cannot eliminate the need for app-managed pause/resume and approval persistence.

### Whether the app can achieve the behavior without forking RubyLLM

Yes, for the product behavior that matters most.

The app can implement the approval model without forking RubyLLM by treating RubyLLM as the transport/execution engine and owning the approval state above it.

What the app can do without a fork:
- Filter tools before registration based on effective policy.
- Enforce execution-time checks inside the adapter before delegating to the real tool.
- Return a structured forbidden result for denied or argument-disallowed calls and let RubyLLM continue the same model flow.
- Stop the run for approval-required calls by changing the adapter/client seam so it can propagate a typed interruption instead of swallowing it.
- Resume later by re-running the message job after the user decides.

What the app cannot do without at least changing its own adapter/client code:
- Use `RubyLLM::Tool::Halt` through the current adapter.
- Bubble an approval-required exception through the current adapter.
- Keep the exact same `complete` call open while waiting for a human decision.

Conclusion:
- No RubyLLM fork is required to ship the behavior.
- Some Small Council adapter/client/job changes are required because the current adapter intentionally swallows the exact control-flow mechanisms the approval model would need.

### `ask_approval` tool and schema-driven approval response

These are viable supporting patterns, not sufficient primary mechanisms.

`ask_approval` tool:
- Could be implemented as an app tool that records an approval request.
- If it simply returns a normal tool result, the model will continue immediately, which does not provide true human approval.
- If it halts or raises, that can become a useful interruption seam, but only after the app changes its adapter/client behavior.
- Conclusion: useful as a product-level abstraction, not enough by itself.

Schema-driven approval response:
- `with_schema` can force the model to emit a structured response such as `{"status":"approval_required", ...}`.
- That can be useful in a separate planning/negotiation step when tools are not being executed.
- It does not replace runtime permission checks, because the actual tool loop remains unchanged once tools are registered and called.
- Conclusion: useful for a two-phase app flow, not a substitute for execution-time authorization.

## 5. Options

### Option A: App-owned approval model on top of stock RubyLLM

Summary:
- Keep RubyLLM unmodified.
- Store approval policy and one-off approval decisions in the app.
- Enforce policy in `AI::ContentGenerator` and `AI::Adapters::RubyLLMToolAdapter`.
- For denied calls, return a structured forbidden tool result and let RubyLLM continue.
- For approval-required calls, interrupt the run at the adapter/client/job seam and resume via a later job after user action.

Pros:
- Lowest delivery risk.
- No gem fork to maintain.
- Keeps product-specific approval semantics where they belong: the app.
- Matches the current async job architecture better than trying to suspend RubyLLM itself.

Cons:
- The approval DSL is app-owned, not a RubyLLM-native API.
- Requires careful adapter changes because the current adapter swallows both halts and exceptions.
- Resume happens as a new run, not the same in-process `complete` stack.

Assessment:
- Best fit for Small Council.

### Option B: Thin local RubyLLM extension or monkey patch

Summary:
- Keep the product behavior app-owned, but reopen RubyLLM locally to add a pre-execution authorization seam and possibly tool metadata helpers.

Pros:
- Cleaner call site than app-only branching in the adapter.
- Could reduce duplication if multiple app entry points eventually need the same tool authorization seam.

Cons:
- Still carries upgrade risk.
- Harder to reason about than a clearly app-owned seam.
- Not materially better unless multiple app features need generic RubyLLM-level policy hooks.

Assessment:
- Viable, but inferior to Option A unless repeated reuse appears.

### Option C: RubyLLM fork or upstream feature first

Summary:
- Add first-class approval metadata and a pre-execution authorizer to RubyLLM, then build the app on top of that API.

Pros:
- Cleanest DSL for `requires_approval` and `allowed_arguments`.
- Could be reusable across apps and providers.
- Makes forbidden-result continuation an explicit engine capability.

Cons:
- Highest scope and slowest path to product value.
- Approval persistence, UI, and async resume still remain app work.
- Risks solving a generic library API before the app semantics are proven.

Assessment:
- Reasonable only if the team explicitly wants to invest in RubyLLM as a reusable approval framework.

### Option D: `ask_approval` / schema-driven orchestration as the primary mechanism

Summary:
- Depend mainly on a special tool or schema response for the model to request approval.

Pros:
- Conceptually simple.
- Keeps the model aware of approval as part of its reasoning.

Cons:
- Does not itself enforce permissions.
- Does not solve actual human-in-the-loop pause/resume.
- Easier for model behavior to drift around than a hard execution-time gate.

Assessment:
- Should be treated only as a supporting UX pattern, not the primary enforcement mechanism.

## 6. Recommendation

Recommendation:
- Use Option A as the main architecture.
- Do not start with a RubyLLM fork.
- If later experience shows the authorization seam is generally useful outside this app, consider extracting the narrowest proven piece upstream into RubyLLM.

Rationale:
- The hard product requirements are app-specific: per-conversation policy, user approval requests, UI actions, exact-match resume behavior, and background-job restart semantics.
- Stock RubyLLM already supports the deny-path continuation pattern once the app returns a forbidden tool result.
- The missing pieces are mostly not provider concerns; they are app orchestration concerns.
- A fork would add scope without removing the need for app persistence and resume handling.

Practical interpretation of the investigation question:
- “Primarily in RubyLLM” is not the best implementation boundary for this app.
- “Primarily in the app, with RubyLLM used as the execution engine and possibly extended later with a small authorization hook” is the better boundary.

## 7. Handoff

- Next workflow:
  - `change`
- Proposed scope for the later change workflow:
  1. Define the app-owned approval policy and approval-request model boundaries.
  2. Add policy resolution before tool registration.
  3. Change the adapter/client seam so approval-required calls can interrupt cleanly and forbidden calls can continue as tool results.
  4. Update the job flow to pause on approval-required and resume on user decision.
  5. Add the minimal conversation UI for proactive policy and pending approval decisions.
  6. Add focused tests around adapter behavior, pause/resume flow, and policy precedence.
- Verification plan for the later change workflow:
  - adapter/client unit tests proving allow, forbid, and approval-required behavior
  - job tests proving pause and resume behavior
  - integration test covering one end-to-end approval flow

## 8. Open questions

- Should a later implementation represent approval-required as a typed exception, a pass-through `RubyLLM::Tool::Halt`, or an app-specific halt result?
  - This remains open because the current task is investigation only.
- Should argument-level policy be exact-match only or support partial schema constraints?
  - This affects product semantics more than RubyLLM feasibility.
- Should the app expose approval to the model as a dedicated `ask_approval` tool, or keep approval entirely out-of-band?
  - Both are feasible, but the enforcement recommendation does not depend on this choice.

## 9. Confidence

- Confidence level: high
- Reason:
  - The key feasibility question is governed by a small number of concrete seams that were directly inspected: `RubyLLM::Chat`, `RubyLLM::Tool`, provider tool serializers, the Small Council adapter, and the background job path.

## 10. Doc impact

- updated:
  - `.ai/plans/2026-03-06-02-ruby-llm-tool-approval-investigation.md`
- deferred:
  - No broader docs updated during investigation.

Approve this plan for a later `change` workflow if you want implementation planning next.
