# Investigation Report: Model interaction request payload missing tools snapshot

1) **Intent**
- **Question to answer:** Do current model interaction request records include the `tools` section sent to the model, and do they snapshot the exact outbound payload?
- **Success criteria:** Evidence-backed root cause, exact code paths for payload assembly/recording, and a concrete fix recommendation for follow-on implementation.

2) **Scope + constraints**
- **In-scope:** Request payload construction, tool registration, interaction recording path, and tests/docs that define intended payload shape.
- **Out-of-scope:** Product code changes.
- **Read-only default acknowledged:** yes
- **Instrumentation/spikes allowed (explicit permission):** no
- **Timebox:** 120 minutes

3) **Evidence collected**
- **Docs inspected (docs-first):**
  - `.ai/workflows/investigate.md`
  - `.ai/docs/features/model-interactions.md`
  - `.ai/docs/patterns/tool-system.md`
  - `.ai/plans/done/2026-02-28-model-interactions.md`
  - `.ai/plans/done/2026-03-01-event-handler-model-interactions.md`
- **Code inspected (file + methods):**
  - `app/libs/ai/client.rb`
    - `chat`
    - `build_ruby_llm_chat`
    - `register_interaction_handler`
  - `app/libs/ai/model_interaction_recorder.rb`
    - `record_chat`
    - `build_chat_request_payload`
    - `build_chat_response_payload`
    - `record_tool_call`
    - `record_tool_result`
    - `format_message`
  - `app/libs/ai/adapters/ruby_llm_tool_adapter.rb`
    - `to_ruby_llm_tool`
    - `create_tool_class`
  - `app/libs/ai/tools/base_tool.rb`
    - `to_ruby_llm_tool`
    - `parameters`
  - `app/libs/ai/content_generator.rb`
    - `build_client`
    - `advisor_tools`
  - `test/ai/unit/model_interaction_recorder_test.rb`
  - `test/ai/unit/client_test.rb`
- **Commands run:**
  - Workspace code search (`grep_search`, `file_search`) for `ModelInteractionRecorder`, `with_tools`, payload-building methods.
  - Read-only file inspection (`read_file`) of above docs/code/tests.
- **Observations:**
  - Tools are attached to RubyLLM chat before completion via `AI::Client#build_ruby_llm_chat` using `chat.with_tools(adapter.to_ruby_llm_tool)`.
  - Request recording for chat interactions is produced by `AI::ModelInteractionRecorder#build_chat_request_payload` after callbacks fire; it only includes `model`, `provider`, `temperature`, optional `system_prompt`, and optional `messages`.
  - `build_chat_request_payload` has no `tools` key and does not read tool definitions from `chat` or adapters.
  - Recorder reconstructs a normalized payload from `chat.messages` + metadata, not an intercepted provider request body.
  - Existing tests validate system prompt/messages payload shape, but no tests assert recording of `tools` or exact outbound payload parity.
  - Historical plan `.ai/plans/done/2026-02-28-model-interactions.md` explicitly described `request_payload` as including `tools`, which drifted from current implementation.

4) **Findings**
- **How it works today (feature map):**
  1. `AI::ContentGenerator#build_client` selects tools via `advisor_tools` and constructs `AI::Client`.
  2. `AI::Client#build_ruby_llm_chat` converts each tool through adapter chain (`BaseTool#to_ruby_llm_tool` -> `RubyLLMToolAdapter#to_ruby_llm_tool`) and registers with `chat.with_tools(...)`.
  3. `AI::Client#register_interaction_handler` installs `on_end_message`, `on_tool_call`, and `on_tool_result` callbacks.
  4. On assistant completion, `ModelInteractionRecorder#record_chat` persists `request_payload` from `build_chat_request_payload`.
- **Answer to investigation question:**
  - **Includes `tools` section?** No (chat request payload omits tools; tool interactions are recorded separately as `interaction_type: "tool"` call/result records).
  - **Snapshots exact outbound payload?** No (payload is reconstructed post hoc from RubyLLM chat state/messages and selected metadata, not captured from the exact provider-bound JSON payload).
- **Root cause:**
  - Current recorder design intentionally reconstructs a canonical payload for display/debug (`build_chat_request_payload`) rather than capturing transport-level outbound request bytes/hash.
  - The reconstruction path never receives or serializes the tool schema collection registered through `chat.with_tools`.
  - Implementation drift vs original design intent/documentation that expected `tools` in `request_payload`.
- **Confidence level:** high

5) **Options**
- **Option A — Minimal parity fix (fast):**
  - Extend `build_chat_request_payload` to include a normalized `tools` array assembled from configured tools/adapters (name, description, parameter schema).
  - Keep current reconstructed-payload architecture.
  - **Pros:** Smallest change, restores missing `tools` visibility.
  - **Cons:** Still not exact outbound payload snapshot.
- **Option B — Exact payload snapshot at call boundary (recommended):**
  - Capture the request payload immediately before provider send in `AI::Client` (single source of truth), including resolved `model`, `temperature`, full messages, and full `tools` definitions as sent.
  - Pass captured payload into `ModelInteractionRecorder#record_chat` (or store on recorder state keyed by turn) instead of rebuilding from `chat.messages`.
  - Keep current tool call/result interaction records unchanged.
  - **Pros:** Meets “ideally exact payload” requirement; avoids drift between sent vs recorded payload.
  - **Cons:** Moderate refactor and tighter coupling to RubyLLM request shape.
- **Option C — Transport interception/observer (most exact, most complex):**
  - Hook lower-level provider client/request instrumentation to persist exact HTTP JSON body.
  - **Pros:** True wire-level fidelity.
  - **Cons:** Highest complexity, provider-specific coupling, likely brittle across gem upgrades.
- **Recommendation + rationale:**
  - **Recommend Option B** as best balance: it can provide near-exact (or exact, depending on access point) outbound payload snapshots including `tools` while remaining app-level and testable.

6) **Handoff**
- **Next workflow:** `change` (bug)
- **Proposed scope (tight):**
  1. Add explicit request snapshot object in `AI::Client` at pre-send boundary and thread it into recorder for `chat` interactions.
  2. Include `tools` in recorded chat `request_payload` using the same structure used at send-time.
  3. Add tests in `test/ai/unit/model_interaction_recorder_test.rb` / `test/ai/unit/client_test.rb` for:
     - `request_payload["tools"]` presence and schema
     - parity between captured request snapshot and persisted payload fields
  4. Update `.ai/docs/features/model-interactions.md` to distinguish chat request snapshot vs tool interaction records.
- **Verification plan:**
  - Targeted unit tests:
    - `bin/rails test test/ai/unit/model_interaction_recorder_test.rb`
    - `bin/rails test test/ai/unit/client_test.rb`
  - Spot-check persisted `ModelInteraction` records in test assertions for `request_payload["tools"]` and expected snapshot keys.

7) **Open questions**
- Can RubyLLM expose the final provider-bound request body directly (including any internal normalization), or should the app treat pre-send client snapshot as the source of truth?
- Should `request_payload` include tool internals beyond public schema (e.g., adapter/runtime metadata), or limit to model-visible tool definitions only?
- For backwards compatibility, do we need to version payload format (`request_payload_version`) when introducing exact snapshots?
