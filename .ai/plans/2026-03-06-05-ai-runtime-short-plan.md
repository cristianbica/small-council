# Short Plan: AI Runtime Refactor, Advisor First

Date: 2026-03-06
Status: In progress; updated to match implementation reality
Change type: refactor
Companion to: [.ai/plans/2026-03-06-04-ai-tasks-agents-runner-refactor-plan.md](.ai/plans/2026-03-06-04-ai-tasks-agents-runner-refactor-plan.md)

## 1. Goal

- Build the new AI runtime in small, reviewable steps.
- Start with advisor details generation only.
- Keep the long plan as the full reference and use this file as the implementation guide.

## 2. Fixed decisions

- Keep these runtime pieces:
  - `AI::Tasks`
  - `AI::Agents`
  - `AI::Runner`
  - `AI::Handlers`
  - `AI::Trackers`
  - `AI::Client` as the RubyLLM boundary
- Put runtime lookup helpers on `AI` itself:
  - `AI.context`
  - `AI.task`
  - `AI.agent`
  - `AI.handler`
  - `AI.tracker`
  - `AI.prompt`
  - `AI.schema`
- `AI.generate_text(...)` is the current high-level utility API.
- `AIRunnerJob`
- `AI::Runner.new(...).run` runs inline.
- `AI::Runner.run(..., async: false)` runs inline.
- `AI::Runner.run(..., async: true)` and `AI::Runner.async(...)` schedule `AIRunnerJob`.
- Runner supports one optional handler.
- The runner currently accepts `task:`, `context:`, `handler:`, and optional extra `tracker:`.
- The task decides the agent.
- `task:`, `context:`, `handler:`, and `tracker:` support the same shapes:
  - symbol
  - class
  - hash with `type:` and params
- Use ERB prompt files.
- Use `AI.schema(...)` for structured output lookup.
- Keep `AI::ContentGenerator` as a temporary facade during migration.
- The new client seam is `AI::Client.chat(model:)`, which returns `AI::Client::Chat`.
- `AI::Client::Chat` currently supports:
  - `add_message`
  - `instructions`
  - `schema`
  - `complete(result)`
- `complete(result)` writes the raw model completion onto `result.response`.
- `AI::Result` remains minimal and currently exposes only `response` and `error`.
- Usage for both legacy and new runtime paths is recorded through `AI::Trackers::UsageTracker`.
- The runner always includes `UsageTracker` and calls trackers after `task.run(result)`.
- `BaseTask#run` owns chat setup/completion; subclasses only implement `prepare(chat)`.
- Prototype constraints for the current slice:
  - `AIRunnerJob` stays a thin wrapper only
  - do not touch legacy `AI::Client` logic
  - do not touch legacy `AI::ContentGenerator` logic
  - keep `AI::Result` minimal
  - keep runtime APIs literal and explicit

## 3. First slice

The first slice is advisor details generation.

It is the right first slice because it is:

- synchronous
- tool-free
- structured
- smaller than conversation work

This slice should prove:

- runner orchestration
- minimal task and agent base classes
- prompt loading
- schema loading
- compatibility wiring through the existing entrypoint

## 4. Directory structure

This is the implementation-first subset of the longer target structure. Existing files such as `app/libs/ai/client.rb` remain in place even when they are not listed here.

### First slice

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

### Added later

```text
app/jobs/
  ai_runner_job.rb

app/libs/ai/
  tools.rb
  contexts/
    conversation_context.rb
  tasks/
    respond_task.rb
  agents/
    advisor_agent.rb
  handlers/
    conversation_handler.rb
```

## 5. Step-by-step plan

### Step 1: Runner base

- Add `AI::Runner` and `AI::Result`.
- Support parameter resolution for `task:`, `context:`, and `handler:` using symbol, class, and hash-with-`type`.
- Keep this step sync-only.

Current status:

- implemented
- runner builds context first, then task, then handler
- runner builds trackers after task and handler resolution
- task owns agent selection
- runner owns tracker and handler execution

Review after this step:

- the runner API is clear
- the parameter rules are clear

### Step 2: Task and agent base

- Add the smallest `BaseTask` and `BaseAgent` needed by the runner.
- Add only agent and prompt declarations.
- Do not add conversation behavior.

Current status:

- implemented
- `BaseTask` declares `agent`
- `BaseAgent` declares `system_prompt`
- `BaseTask#run` builds the chat and calls `prepare(chat)`

Review after this step:

- one utility run can be expressed cleanly
- no extra DSL has appeared

### Step 3: Advisor details task assets

- Add the first concrete utility task shape for advisor details.
- Add the utility agent.
- Add the direct chat helper used by the new runtime path.
- Add the minimal context object for utility runs.
- Add the advisor details prompt file.
- Add the `advisor_profile` schema.

Current status:

- implemented
- current path is `TextTask` + `TextWriterAgent` + `SpaceContext` + `AI::Client::Chat`

Review after this step:

- advisor details generation is fully expressible through the new runtime

### Step 4: Wire the existing flow

- Route a real utility generation path through the new runtime.
- Keep `AI::ContentGenerator` as the temporary facade where that keeps the change smaller.
- Allow direct `AI.generate_text(...)` callers when that is the simpler integration.

Current status:

- implemented first for advisor profile generation via `AI::ContentGenerator#generate_advisor_profile`
- current form-based generation now uses `FormFillersController#create` + `AI.generate_text(..., async: true)` directly

Review after this step:

- one real feature runs through the new runtime
- the current user-facing utility flow is no longer tied to the old advisor controller endpoint

### Step 5: Focused tests

- Current reality now includes runtime-adjacent tests for the new utility slices.

Current status:

- runner coverage exists
- form filler controller coverage exists
- council-profile prompt coverage exists
- advisor and council form tests now assert form-filler integration

### Step 6: Council description

- Reuse the same runtime shape for council description generation.
- Do not add new architecture here.

Current status:

- implemented for the current `council_profile` form-filler slice
- legacy `generate_description` endpoints were removed from the current UI flow

Review after this step:

- the runtime handles more than one utility generation cleanly

### Step 7: Async entrypoint

- Add `AI::Runner.async(...)`.
- Add `AI::Runner.run(..., async: true)` as the unified async toggle.
- Add `AIRunnerJob` as the only async runner job.
- Reuse the same orchestration path as sync execution.

Current status:

- implemented

Review after this step:

- sync and async share one path

## 6. Deferred until later

- conversation reply generation
- `RespondTask`
- advisor conversation agent behavior
- typed conversation contexts beyond `SpaceContext`
- conversation-specific handler flows
- tool-path migration
- slash-command removal
- scribe cleanup

Conversation work starts only after the advisor details and council description slices are proven.

## 7. Reality notes

- The plan originally assumed separate root lookup wrapper files; the implementation moved lookup helpers directly onto `AI` and removed the empty wrapper files.
- The plan originally assumed a runner-provided `agent:` input; the implementation instead made task-owned agent resolution the primary contract.
- The plan originally assumed a more RubyLLM-like `Chat#complete`; the implementation currently uses `complete(result)` so the chat object can write directly to `AI::Result`.
- The plan originally described broader typed contexts; the implementation intentionally started with only `BaseContext` and `SpaceContext`.
- The runner now owns tracker execution and always includes `AI::Trackers::UsageTracker`.
- The advisor-profile compatibility wiring first went live through `AI::ContentGenerator`, but the current user-facing utility flow is the reusable form-filler path.
- The current async utility path is `FormFillersController#create` -> `AI.generate_text(... async: true, handler: { type: :turbo_form_filler, ... })` -> `AI::Handlers::TurboFormFillerHandler`.
- `advisor_profile` and `council_profile` are both implemented utility profiles in the current form-filler flow.
- `AdvisorsController#generate_prompt` and `CouncilsController#generate_description` are no longer part of the current implementation.
- Async execution and usage tracking are now part of the implemented runtime slice.

## 8. Next approval

The next substantial implementation step is conversation runtime work: add `RespondTask`, conversation-specific contexts, and the first real conversation handler flow.
