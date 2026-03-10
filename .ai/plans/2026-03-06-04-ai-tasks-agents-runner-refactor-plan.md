# Refactor Plan: AI::Tasks + AI::Agents + AI::Runner

Date: 2026-03-06
Status: In progress; updated to match implementation reality
Change type: refactor
Supersedes for implementation planning: [.ai/plans/2026-03-06-03-ai-simplification-investigation.md](.ai/plans/2026-03-06-03-ai-simplification-investigation.md)

## 1. Goal

- Replace the current AI runtime shape with explicit `AI::Tasks`, `AI::Agents`, and `AI::Runner` boundaries.
- Keep the migration incremental and compatible with the current jobs/controllers while moving tool selection, prompt ownership, structured output, and persistence hooks into clearer seams.
- Stay aligned with the prior simplification goals: reduce custom glue, remove slash commands, decouple app orchestration from RubyLLM transport concerns, and adopt RubyLLM features where they shrink code instead of obscuring it.

## 2. Non-goals

- No implementation in this workflow.
- No DB schema redesign for persisted tool definitions yet.
- No product/UI redesign beyond removing slash-command references when that migration phase happens.
- No provider/model admin redesign; retain current `AI::Client` provider operations unless a later change uncovers a specific need.

## 3. Evidence snapshot

- The current runtime is centered on `AI::ContentGenerator`, which owns prompt templates, tool selection, message shaping, cache keys, and multiple task entrypoints in [app/libs/ai/content_generator.rb#L1](app/libs/ai/content_generator.rb#L1).
- `AI::Client` currently owns transport plus runtime policy injection, tool adapter wiring, usage tracking, and model-interaction recording in [app/libs/ai/client.rb#L1](app/libs/ai/client.rb#L1).
- `GenerateAdvisorResponseJob` depends directly on `AI::ContentGenerator` for both normal advisor replies and scribe follow-ups in [app/jobs/generate_advisor_response_job.rb#L1](app/jobs/generate_advisor_response_job.rb#L1).
- Utility generations are now split across two paths:
  - conversation title generation still depends on [app/jobs/generate_conversation_title_job.rb#L1](app/jobs/generate_conversation_title_job.rb#L1)
  - advisor and council form-filling now goes through [app/controllers/form_fillers_controller.rb#L1](app/controllers/form_fillers_controller.rb#L1) and `AI.generate_text(...)`
- Tool wiring is a hardcoded array in `AI::ContentGenerator#advisor_tools`, and `AskAdvisorTool` exists but is not wired today in [app/libs/ai/content_generator.rb#L314](app/libs/ai/content_generator.rb#L314) and [app/libs/ai/tools/conversations/ask_advisor_tool.rb#L1](app/libs/ai/tools/conversations/ask_advisor_tool.rb#L1).
- Context is currently a broad hash built by `AI::ContextBuilders::ConversationContextBuilder` in [app/libs/ai/context_builders/conversation_context_builder.rb#L1](app/libs/ai/context_builders/conversation_context_builder.rb#L1).
- Slash-command support is narrow and redundant: only `/invite` exists in [app/services/command_parser.rb#L1](app/services/command_parser.rb#L1), while deterministic invite behavior already exists elsewhere.
- The auto-created Scribe prompt is embedded in the model layer in [app/models/space.rb#L29](app/models/space.rb#L29), which is the wrong long-term owner once agents become first-class runtime objects.

## 4. Recommendation summary

### 4.1 Public architecture

- Runtime lookup entrypoints now live on `AI` itself:
  - `AI.context`
  - `AI.task`
  - `AI.agent`
  - `AI.handler`
  - `AI.tracker`
  - `AI.prompt`
  - `AI.schema`
- `AI.generate_text(...)` is the current convenience entrypoint for utility text generation.
- `AI::Tasks`, `AI::Agents`, `AI::Handlers`, `AI::Trackers`, and future `AI::Tools` remain the implementation namespaces.
- `AI::Runner` executes a task against a context, runs trackers, and may invoke one handler after the task run completes.
- The task decides the agent; the runner does not accept `agent:` in the current implementation.
- `AIRunnerJob` is now implemented as the async entrypoint for runner execution.
- `AI::Client` remains the RubyLLM boundary and now also exposes a class-level chat factory for the new runtime path.
- `AI::Trackers` currently means runner-owned post-run tracking, with `UsageTracker` implemented first.
- The first implementation slice should be advisor details generation; conversation work should start later.

### 4.2 Task granularity recommendation

- Current implemented task surface:
  - `AI::Tasks::BaseTask`
  - `AI::Tasks::TextTask`
- `AI::Tasks::RespondTask` remains planned, not implemented.
- Use `TextTask` for utility generations.
- Use `RespondTask` only for conversation replies.

### 4.3 Fate of `AI::ContentGenerator`

- Recommend keeping `AI::ContentGenerator` temporarily as a compatibility facade.
- During migration it should delegate each existing public method to a concrete `AI::Task` + `AI::Agent` + `AI::Runner` combination.
- Once all callers are migrated to the new APIs and tests no longer target the old facade, remove it.

### 4.4 Naming rules

- Runtime lookup entrypoints are explicit helper methods on `AI`, not separate plural root lookup modules.
- Nested constants still hold the actual classes.
- The current implementation uses minimal class attributes rather than a broader DSL:
  - tasks declare `agent`
  - agents declare `system_prompt`
- `AI.context/task/agent/handler/tracker/schema` resolve symbols and classes directly.

### 4.5 Current implemented decisions

- Runner entrypoints are now:
  - `AI::Runner.new(task:, context:, handler: nil, tracker: nil).run`
  - `AI::Runner.run(task:, context:, handler: nil, tracker: nil, async: false)`
  - `AI::Runner.async(task:, context:, handler: nil, tracker: nil)`
- Runner initialization order is:
  - build context
  - build task with context
  - build handler
  - build trackers
- Runner execution order is:
  - initialize blank `AI::Result`
  - call `task.run(result)`
  - call each tracker with `track(result)`
  - call `handler.handle(result)` when present
  - return the result
- When a handler exists and the run raises, the runner stores the exception on `result.error`, still invokes the handler, and returns the failed result.
- The result should stay minimal during prototyping; do not attach task, context, or handler objects onto it.
- `AI::Result` currently exposes only `response` and `error`.
- Tasks own agent resolution via `BaseTask#agent`.
- The first concrete runtime path is utility text generation through `TextTask` + `TextWriterAgent` + `SpaceContext`.
- `AI::Client.chat(model:)` returns `AI::Client::Chat`.
- `AI::Client::Chat` is a direct RubyLLM-shaped helper stored in `app/libs/ai/client/chat.rb`.
- The current chat helper supports:
  - `add_message`
  - `instructions`
  - `schema`
  - `complete(result)`
- `complete(result)` currently writes the raw RubyLLM completion onto `result.response`.
- `AI::Trackers::UsageTracker` is runner-owned, instance-based, and records usage through `track(result)`.
- The runner always includes `UsageTracker` and may append one optional extra tracker.
- `AI::Contexts::BaseContext` stores arbitrary extra args and exposes `[]` / `key?` helpers.
- `AI::Tasks::BaseTask#run` owns chat setup and completion; subclasses only implement `prepare(chat)`.
- `AI.generate_text(...)` is the current high-level utility API and passes explicit `handler:` and `async:` options through to the runner.
- The current async UI utility path is the reusable form-filler flow:
  - `FormFillersController#create`
  - `AI.generate_text(..., async: true, handler: { type: :turbo_form_filler, ... })`
  - `AI::Handlers::TurboFormFillerHandler`
- The legacy instance `AI::Client#chat` path remains in place for the existing app runtime.
- Prototyping constraints for the current slice:
  - do not touch legacy `AI::Client` behavior such as `track_usage`
  - do not touch legacy `AI::ContentGenerator` behavior
  - keep `AIRunnerJob` as a thin wrapper that only runs `AI::Runner.new(task:, context:, handler:).run`
  - keep public runtime APIs literal and explicit

## 5. Proposed class/module layout

### 5.1 Runtime layout

```text
app/libs/ai/
  ai.rb
  runner.rb
  client.rb
  result.rb
  client/
    chat.rb
  tasks/
    base_task.rb
    text_task.rb
  agents/
    base_agent.rb
    text_writer_agent.rb
  contexts/
    base_context.rb
    space_context.rb
  handlers/
    base_handler.rb
    turbo_form_filler_handler.rb
  trackers/
    usage_tracker.rb
  prompts/
    agents/
      text_writer.erb
    tasks/
      advisor_profile.erb
      council_profile.erb
  schemas/
    advisor_profile_schema.rb
    council_profile_schema.rb
```

Planned later but not implemented yet:

```text
app/libs/ai/
  tools.rb
  tasks/
    respond_task.rb
  agents/
    advisor_agent.rb
  handlers/
    conversation_handler.rb
  contexts/
    conversation_context.rb
```

### 5.2 Responsibilities and boundaries

#### `AI::Tasks::BaseTask`

- Initialized with `context:`.
- Declares one class-level `agent` name.
- Resolves the agent lazily through `AI.agent(...)`.
- Owns the shared chat lifecycle:
  - build `AI::Client.chat(model: context.model)`
  - call `prepare(chat)`
  - call `chat.complete(result)`
- Must not choose models directly and must not know about RubyLLM.

#### `AI::Tasks::TextTask`

- Shared task for prompt-driven generation.
- Good fit for titles, descriptions, profiles, and other structured text outputs.
- Initialized with `prompt:`, optional `schema:`, and optional `description:`.
- `prepare(chat)` attaches schema, agent instructions, and the rendered task prompt.

#### `AI::Tasks::RespondTask`

- Specialized task for conversation replies.
- Owns thread-aware message assembly and reply-specific prompt behavior.
- Handles both normal advisor replies and Scribe replies through the selected agent rather than through separate task classes.

#### `AI::Agents::BaseAgent`

- Declares one class-level `system_prompt` path.
- Resolves the prompt text through `AI.prompt(...)`.
- Holds instructions and runtime helpers.
- Must not know which controller/job invoked it.

#### `AI::Agents::TextWriterAgent`

- Default non-conversation agent.
- Best fit for `TextTask` runs.

#### `AI::Agents::AdvisorAgent`

- Single advisor-oriented agent type for both regular advisors and Scribe.
- Uses `agents/advisor` prompt content plus advisor-specific overlays from records.
- Scribe is just an advisor with different prompt data and tool ids.

#### `AI::Runner`

- Sole runtime orchestration entrypoint.
- Accepts `task:`, `context:`, optional `handler:`, and optional extra `tracker:`.
- Public execution shape:
  - `AI::Runner.new(...).run` executes inline
  - `AI::Runner.run(..., async: false)` executes inline
  - `AI::Runner.run(..., async: true)` delegates to `AI::Runner.async(...)`
  - `AI::Runner.async(...)` enqueues `AIRunnerJob`
- Responsibilities:
  - build context, task, handler, and tracker objects from symbol/class/hash input
  - create a blank `AI::Result`
  - delegate execution to the task
  - invoke runner-owned trackers after task execution
  - invoke one handler after the run when a handler is provided
  - if a handler exists, surface failures through `result.error` and still hand the result to the handler
  - return `AI::Result`
- Must not contain product-specific prompt strings.

#### `AIRunnerJob`

- Implemented as the async execution wrapper used by `AI::Runner.async(...)` and `AI::Runner.run(..., async: true)`.
- Reuses the same runner execution path as sync execution.
- During the current prototype it remains a thin wrapper around `AI::Runner.new(task:, context:, handler:, tracker:).run` only.

#### Runner parameter resolution

- `context:`, `handler:`, and `tracker:` follow the same calling rule.
- `task:` follows the same resolution pattern, but is initialized with `context:`.
- Supported forms:
  - symbol: resolve by name, then initialize
  - class: initialize the class directly
  - hash: resolve `type`, then initialize with the remaining params
- The runner always builds one `UsageTracker` instance and appends one optional extra tracker when provided.
- The same rule applies to `task:`, `context:`, `handler:`, and `tracker:` so callers can stay concise without giving up explicit constants where they help readability.

#### `AI::Handlers::BaseHandler`

- Base type for post-run application behavior.
- Receives the resolved task and context at initialization time, then handles the finished run result.
- Keeps post-run actions out of tasks and out of `AI::Client`.

#### `AI::Handlers::ConversationHandler`

- Applies conversation-specific side effects after a response run.
- Good fit for conversation state changes that should happen after the model result is available.

#### `AI::Handlers::TurboFormFillerHandler`

- Publishes form-filler utility results to a Turbo stream keyed by `filler_id`.
- Broadcasts success or error state back into the pending form-filler UI.
- Good fit for async utility generations where the model output should update a resource form after job completion.

#### `AI::Client`

- Retained as the RubyLLM integration boundary.
- Responsibilities after refactor:
  - provider/model configuration
  - class-level `chat(model:)` factory for the new runtime path
  - direct chat/completion execution through `AI::Client::Chat`
  - legacy instance `chat` / `complete` execution for the existing app path
  - tool adapter registration for the legacy path
  - structured-output support via `Chat#schema`
  - event callback hookup used by persistence hooks on the legacy path
  - provider utility methods `list_models` and `test_connection`
- Responsibilities to remove from `AI::Client`:
  - business-specific policy string assembly
  - conversation/council prompt shaping
  - deciding which tools an agent gets beyond using explicit declarations provided by the task/agent

#### Context objects

- The current implementation uses a narrower minimal context layer:
  - `AI::Contexts::BaseContext`
  - `AI::Contexts::SpaceContext`
- `SpaceContext#model` is currently the key contract the new runtime depends on.
- Conversation-specific typed contexts remain planned for later.

#### Root lookups

- Persist names, not Ruby class names.
- Use `AI.context/task/agent/handler/tracker/prompt/schema` only where runtime resolution is needed.

#### Trackers

- `AI::Trackers::UsageTracker` wraps current `UsageRecord` creation.
- Trackers are instance objects invoked by the runner with `track(result)`.
- The runner owns tracker execution in the same way it owns handler execution.
- The current implementation has `AI::Client#track_usage` delegating to `AI::Trackers::UsageTracker` for the legacy path.
- The new runtime path records usage through runner-owned `AI::Trackers::UsageTracker`, not inside `AI::Client::Chat#complete(result)`.

#### `AI.prompt`

- Replace the dedicated prompt loader object with a small prompt API:
  - `AI.prompt("agents/text_writer")`
  - `AI.prompt("tasks/respond")`
- Resolution rule:
  - `AI.prompt("agents/text_writer")` maps to `app/libs/ai/prompts/agents/text_writer.erb`
  - `AI.prompt("tasks/conversation_title")` maps to `app/libs/ai/prompts/tasks/conversation_title.erb`
- Prompt files are ERB templates and may interpolate context-derived values or light presentation logic.
- The API should return rendered prompt text.

#### `AI.schema`

- Provide a small schema lookup API:
  - `AI.schema("conversation_title")`
  - `AI.schema("advisor_profile")`
- In the current implementation, lookup returns schema classes.
- Those classes are accepted by RubyLLM because `with_schema` instantiates schema classes and accepts objects responding to `to_json_schema`.

## 6. Prompt storage strategy

### 6.1 Recommendation

- Use prompt files.
- Store long-lived agent instructions and task prompt scaffolds in `app/libs/ai/prompts/**/*.erb`.
- Keep dynamic, record-specific data outside the files and inject it through prompt variables or typed context serialization.

### 6.2 Why prompt files make sense here

- The current runtime already has long prompt bodies embedded in Ruby strings in [app/libs/ai/content_generator.rb#L29](app/libs/ai/content_generator.rb#L29) and [app/models/space.rb#L29](app/models/space.rb#L29).
- Prompt files will make agent/task ownership explicit and reduce prompt drift between model code, jobs, and controllers.
- They are especially useful for:
  - shared advisor/scribe instruction scaffolds
  - structured-output utility tasks
  - future prompt reviews without hunting through Ruby methods

### 6.3 Prompt layering

- Recommended composition order:
  1. agent prompt file
  2. persisted agent instructions from records when applicable
  3. task prompt file
  4. serialized context/messages
- `AdvisorAgent` composes the base advisor prompt with `advisor.system_prompt`.
- `TextWriterAgent` owns neutral utility-generation instructions.

### 6.4 File format recommendation

- Use ERB prompt files.
- Allow interpolation from task, agent, and context data.
- Keep the ERB disciplined:
  - prefer straightforward variable interpolation
  - allow small presentation branches when necessary
  - avoid embedding complex business logic in prompt templates

## 7. Tool reorganization plan

### 7.1 Naming convention

- Use `domain/action_object` path identifiers.
- Keep domain names plural to match current user terminology and future DB storage.
- Examples:
  - `external/browse_web`
  - `memories/create_memory`
  - `conversations/query_conversations`
  - `councils/list_councils`

### 7.2 Agent tool declarations

- `AdvisorAgent` exposes direct `tool_ids` from advisor data.
- Scribe is just an advisor with broader `tool_ids`.
- Non-scribe advisors start with no tools unless explicitly allowed.
- Tasks may narrow tool access for a specific run.

### 7.3 Migration map from current class names

| Current class/file | Proposed class/file | Path identifier |
|---|---|---|
| `AI::Tools::External::BrowseWebTool` | `AI::Tools::External::BrowseWeb` | `external/browse_web` |
| `AI::Tools::Internal::CreateMemoryTool` | `AI::Tools::Memories::CreateMemory` | `memories/create_memory` |
| `AI::Tools::Internal::ListMemoriesTool` | `AI::Tools::Memories::ListMemories` | `memories/list_memories` |
| `AI::Tools::Internal::QueryMemoriesTool` | `AI::Tools::Memories::QueryMemories` | `memories/query_memories` |
| `AI::Tools::Internal::ReadMemoryTool` | `AI::Tools::Memories::ReadMemory` | `memories/read_memory` |
| `AI::Tools::Internal::UpdateMemoryTool` | `AI::Tools::Memories::UpdateMemory` | `memories/update_memory` |
| `AI::Tools::Internal::GetConversationSummaryTool` | `AI::Tools::Conversations::GetConversationSummary` | `conversations/get_conversation_summary` |
| `AI::Tools::Internal::ListConversationsTool` | `AI::Tools::Conversations::ListConversations` | `conversations/list_conversations` |
| `AI::Tools::Internal::QueryConversationsTool` | `AI::Tools::Conversations::QueryConversations` | `conversations/query_conversations` |
| `AI::Tools::Internal::ReadConversationTool` | `AI::Tools::Conversations::ReadConversation` | `conversations/read_conversation` |
| `AI::Tools::Conversations::AskAdvisorTool` | `AI::Tools::Conversations::AskAdvisor` | `conversations/ask_advisor` |
| `AI::Tools::Internal::CreateAdvisorTool` | `AI::Tools::Advisors::CreateAdvisor` | `advisors/create_advisor` |
| `AI::Tools::Internal::GetAdvisorTool` | `AI::Tools::Advisors::GetAdvisor` | `advisors/get_advisor` |
| `AI::Tools::Internal::ListAdvisorsTool` | `AI::Tools::Advisors::ListAdvisors` | `advisors/list_advisors` |
| `AI::Tools::Internal::UpdateAdvisorTool` | `AI::Tools::Advisors::UpdateAdvisor` | `advisors/update_advisor` |
| `AI::Tools::Internal::CreateCouncilTool` | `AI::Tools::Councils::CreateCouncil` | `councils/create_council` |
| `AI::Tools::Internal::GetCouncilTool` | `AI::Tools::Councils::GetCouncil` | `councils/get_council` |
| `AI::Tools::Internal::ListCouncilsTool` | `AI::Tools::Councils::ListCouncils` | `councils/list_councils` |
| `AI::Tools::Internal::UpdateCouncilTool` | `AI::Tools::Councils::UpdateCouncil` | `councils/update_council` |
| `AI::Tools::Internal::AssignAdvisorToCouncilTool` | `AI::Tools::Councils::AssignAdvisor` | `councils/assign_advisor` |
| `AI::Tools::Internal::UnassignAdvisorFromCouncilTool` | `AI::Tools::Councils::UnassignAdvisor` | `councils/unassign_advisor` |

### 7.4 Migration notes

- Preserve the current classes temporarily as thin subclasses or aliases where tests/callers still reference them.
- The lookup modules should support alias resolution during migration so both old code and new persisted identifiers can coexist.
- Do not persist Ruby class names anywhere new; only persist the path identifier.

## 8. Structured output plan

### 8.1 First adopters

- Adopt structured output first for:
  - advisor profile generation
  - council profile generation
  - title generation
- Do not apply structured output first to conversation reply generation. That path is tool-heavy, conversational, and already has more moving parts.

### 8.2 Task schema declaration

- Structured tasks declare a schema name for `AI.schema(...)` or return a schema object directly.
- Initial schema names:
  - `conversation_title`
  - `advisor_profile`
  - `council_profile`
- Backing objects are `RubyLLM::Schema` instances.
- `AI::Runner` should validate structured output before returning `AI::Result`.

### 8.3 Fallback and error handling

- Preferred path:
  - provider supports structured output
  - runner requests schema directly through `AI::Client`
  - runner validates and returns typed hash/value object
- Fallback path:
  - if provider lacks structured-output support, runner can perform one compatibility attempt using a JSON-focused prompt and then validate locally
  - if validation fails, raise a task-specific schema error and do not silently coerce malformed data
- Error policy:
  - utility tasks fail closed with explicit validation errors
  - conversation tasks without schemas keep current freeform behavior
  - tracker hooks should record validation failures as run metadata so failures are inspectable

## 9. Phased migration plan

### Step 1: Runner base

- Build the new runtime in parallel with the current AI path.
- Add the minimum synchronous runner skeleton:
  - `AI::Runner`
  - `AI::Result`
- Add runner parameter resolution for `task:`, `context:`, and `handler:` using symbol, class, and hash-with-`type` inputs.
- Keep this step sync-only.
- Do not change controllers, jobs, or existing entrypoints yet.

Status: implemented.

### Step 2: Task and agent base

- Add the smallest `AI::Tasks::BaseTask` and `AI::Agents::BaseAgent` needed by the runner.
- Add only the declarations needed for agent and prompt lookup.
- Keep this utility-only.
- Do not add conversation behavior, tool logic, or context specialization here.

Status: implemented with minimal class-attribute-based declarations.

### Step 3: Advisor details slice

- Add the first concrete utility path for advisor details generation:
  - `TextTask`
  - `TextWriterAgent`
  - `AI::Client::Chat`
  - `SpaceContext`
  - `tasks/advisor_profile` prompt
  - `advisor_profile` schema
- Reuse the existing `AI::Client` boundary.
- Keep this slice tool-free and synchronous.

Status: implemented in the new runtime path.

### Step 4: Compatibility wiring

- Route an existing utility generation path through the new runtime.
- Keep the smallest practical caller surface for each slice.
- Keep `AI::ContentGenerator` as a delegating facade where it still reduces migration risk.
- Allow later utility consumers to call `AI.generate_text(...)` directly when that is the smaller integration.

Status: implemented first through `AI::ContentGenerator#generate_advisor_profile`, then extended in the current UI slice through `FormFillersController#create` calling `AI.generate_text(...)` directly.

### Step 5: Focused tests

- Add coverage for:
  - runner parameter resolution
  - advisor profile schema validation
  - the current utility entrypoints using the new runtime underneath

Status: partially implemented for the current runtime and form-filler slices.

- runner behavior is covered
- council-profile prompt rendering is covered
- form filler controller flows are covered
- advisor and council forms now assert form-filler integration instead of the removed content-generator flow

### Step 6: Next utility slice

- Migrate council profile generation using the same runtime shape.
- Optionally migrate conversation title generation after that, still as a utility task.
- Do not add new architecture in this step unless the utility path exposes a clear gap.

Status: implemented for the current council form-filler profile slice.

- `council_profile` prompt and schema exist
- `FormFillersController` supports `council_profile`
- the old `CouncilsController#generate_description` endpoint has been removed from the current UI flow

### Step 7: Async entrypoint

- Add `AI::Runner.async(...)`.
- Add `AI::Runner.run(..., async: true)` as the unified public async toggle.
- Add `AIRunnerJob` as the single async entrypoint.
- Reuse the same orchestration path as `AI::Runner.new(...).run`.

Status: implemented.

### Step 8: Conversation runtime

- Introduce conversation-specific runtime pieces only after the utility path is proven:
  - `RespondTask`
  - `AdvisorAgent`
  - typed conversation contexts
  - concrete handler flows where needed
- Migrate `GenerateAdvisorResponseJob` behavior into the new runtime path.
- Move business policy strings out of `AI::Client` and into agent/task prompt assets.

### Step 9: Tool and compatibility cleanup

- Add `AI::Tools` lookup helpers and agent-owned tool declarations.
- Reorganize tools into domain namespaces and map path identifiers through the module lookup.
- Remove slash-command support when conversation migration makes it safe to do so.
- Remove `AI::ContentGenerator` once no callers depend on it.
- Remove obsolete context-builder wrappers and temporary tool aliases when no longer needed.

## 10. Current files likely replaced, slimmed, or retained

### Likely replaced

- `app/jobs/generate_advisor_response_job.rb`
- `app/jobs/generate_conversation_title_job.rb`
- `app/services/command_parser.rb`
- `app/services/commands/` subtree
- large portions of `app/libs/ai/content_generator.rb`
- large portions of `app/libs/ai/context_builders/`

### Likely slimmed down

- `app/libs/ai/client.rb`: keep transport/provider responsibilities; remove business-specific policy and prompt ownership
- `app/controllers/advisors_controller.rb`: advisor-profile generation endpoint has already been removed from the current UI flow
- `app/controllers/councils_controller.rb`: council-description generation endpoint has already been removed from the current UI flow
- `app/controllers/form_fillers_controller.rb`: current HTTP surface for async utility form filling
- `app/models/space.rb`: stop embedding the full Scribe prompt inline and treat Scribe as advisor data plus agent overlays

### Likely retained

- `app/jobs/ai_runner_job.rb`: single async runner job used by `AI::Runner.async(...)` and `AI::Runner.run(..., async: true)`
- `app/libs/ai/model.rb`
- `app/libs/ai/model_manager.rb`
- `app/libs/ai/adapters/ruby_llm_tool_adapter.rb` or a near-equivalent adapter under the tool/client layer
- `app/libs/ai/model_interaction_recorder.rb` logic, likely moved or wrapped under `AI::Trackers`
- current `ModelInteraction` and `UsageRecord` persistence models
- `ConversationLifecycle` as the app-owned conversation orchestration layer after command logic is removed

## 11. Risks and open design decisions

### Risks

- Prompt drift during the migration if prompt ownership moves before tests cover old and new outputs.
- Overdesign risk if the first slice tries to migrate tool-heavy conversation responses before the utility-task path is proven.
- Compatibility risk around existing tests that mock `AI::ContentGenerator` directly.
- Scribe behavior may regress if prompt-file migration and slash-command removal happen before tool-authorization tests exist.

### Open design decisions

- Whether `AI::Client` keeps instance initialization with `model:` or shifts to a request-object API owned by `AI::Runner`.
- Whether `advisor.system_prompt` remains an editable overlay on top of `AI::Agents::AdvisorAgent` base instructions, or whether part of it should become task-owned prompt content.
- Whether `conversations/ask_advisor` should be activated in the first tool-registry migration or left dormant until the new runtime is stable.
- Whether alias classes for old tool names should exist in code, or only in registry metadata.
- How much ERB logic is acceptable inside prompt files before it should move back into Ruby serialization helpers.

## 12. Implementation reality summary

- The implementation intentionally deviated from the earlier plan in these places:
  - runtime lookups moved onto explicit `AI` helper methods instead of separate plural lookup wrapper files
  - runner does not take `agent:`; the task owns agent resolution
  - contexts are currently `BaseContext` + `SpaceContext`, not `RunContext` + `ConversationContext`
  - the new client seam is `AI::Client.chat(model:) -> AI::Client::Chat`
  - `AI::Client::Chat#complete(result)` mutates the runner result instead of returning a normalized `AI::Model::Response`
  - schemas are class-based lookups rather than pre-instantiated schema objects
- Additional implemented reality:
  - empty shell files such as `app/libs/ai/prompts.rb`, `schemas.rb`, `tasks.rb`, `agents.rb`, `contexts.rb`, and `handlers.rb` have been removed
  - the runner owns tracker execution and always includes `AI::Trackers::UsageTracker`
  - `BaseTask#run` owns chat initialization/completion and subclasses implement `prepare(chat)`
  - `AI.generate_text(...)` is the current convenience API for utility text generation
  - advisor-profile compatibility wiring first went live through `AI::ContentGenerator`, but the current user-facing utility flow now runs through `FormFillersController#create`
  - async execution is available through `AI::Runner.async(...)`, `AI::Runner.run(..., async: true)`, and `AIRunnerJob`
  - usage tracking is available on both the legacy client path and the new runtime path through `AI::Trackers::UsageTracker`
  - the current reusable async utility UI consists of:
    - `FormFillersController`
    - `AI::Handlers::TurboFormFillerHandler`
    - `form_filler_controller.js`
    - advisor and council form integrations
  - `AdvisorsController#generate_prompt` and `CouncilsController#generate_description` are no longer part of the current implementation
- These are the correct current decisions and this plan now reflects them.

## 13. Exact approval questions for the user

1. Approve the public architecture of `AI::Tasks`, `AI::Agents`, `AI::Runner`, with `AI::ContentGenerator` retained only as a temporary compatibility facade?
2. Approve the reduced task surface of `BaseTask`, `TextTask`, and `RespondTask`, with utility generations expressed as `TextTask` instances instead of one task class per workflow?
3. Approve ERB prompt files under `app/libs/ai/prompts/**/*.erb`, accessed via `AI.prompt("...")`, with agent prompts layered ahead of task prompts and persisted advisor prompts treated as overlays?
4. Approve the path-identifier convention `domain/action_object` for tools, with future persistence using identifiers like `councils/list_councils` rather than Ruby class names?
5. Approve the implementation strategy of building the new stack in parallel with the current infrastructure, then migrating flows incrementally from the advisor utility slice into reusable async utility consumers such as the form-filler flow?
6. Approve treating Scribe as an `AdvisorAgent` variant with broader `tool_ids` and prompt overlays, instead of a separate `ScribeAgent` class?

## 14. Verification

- Discovery commands run for this planning task: none; this plan is based on file inspection and workspace search.
- Verification to require during implementation:
  - `bin/rails test test/jobs/generate_conversation_title_job_test.rb`
  - `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
  - `bin/rails test test/integration/ai_response_flow_test.rb`
  - `bin/rails test test/controllers`
  - `bin/rails test test/ai`

## 15. Doc impact

- updated: this plan artifact
- expected follow-up doc updates during implementation:
  - `.ai/docs/features/ai-integration.md`
  - `.ai/docs/patterns/tool-system.md`
  - `.ai/docs/patterns/command-pattern.md` or removal if slash commands are fully deleted

Approve this plan?
