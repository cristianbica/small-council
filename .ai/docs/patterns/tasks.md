# Tasks

How AI tasks execute through `AI::Runner` and connect to agents, prompts, tools, handlers, and trackers.

## Entry Points

Main API methods in `app/libs/ai.rb`:

- `AI.run(task:, context:, handler: nil, tracker: nil, async: false)`
- `AI.generate_advisor_response(...)` -> wraps a `respond` task in conversation context.
- `AI.generate_text(...)` -> wraps a `text` task in space context.
- `AI.compact_conversation(...)` -> wraps a `text` task in conversation context for compaction.

## Task Types

- `AI::Tasks::RespondTask` (`app/libs/ai/tasks/respond_task.rb`)
  - Agent: `:advisor`
  - Used for advisor/scribe chat replies.
- `AI::Tasks::TextTask` (`app/libs/ai/tasks/text_task.rb`)
  - Agent: `:text_writer`
  - Used for utility generation (form filling, title generation, compaction, etc.).

Both inherit from `AI::Tasks::BaseTask`.

## Lifecycle

`AI::Runner` (`app/libs/ai/runner.rb`) orchestrates execution:

1. Build context via `AI.context(...)`.
2. Build task via `AI.task(...)`.
3. Build optional handler via `AI.handler(...)`.
4. Build trackers:
   - always includes `AI::Trackers::UsageTracker`
   - optionally adds custom tracker (`AI.tracker(...)`), e.g. `:model_interaction`.
5. Execute `task.run(result, trackers: trackers)`.
6. Run tracker `track(result)` callbacks.
7. Invoke handler `handle(result)` if configured.

For `async: true`, execution is delegated to `AIRunnerJob` (`app/jobs/ai_runner_job.rb`).

## Base Task Execution

`AI::Tasks::BaseTask#run` performs the shared flow:

1. Create chat session: `AI::Client.chat(model: context.model)`.
2. Register tools from agent tool refs.
3. Call `prepare(chat)` (task-specific prompt/message setup).
4. Register tracker hooks on chat (`tracker.register(chat)` when supported).
5. Complete the chat and populate `AI::Result`.

## Relationship to Agents and Tools

- Tasks choose an agent with `self.agent = ...`.
- Task asks `agent.tools` for tool refs.
- `AI.tools(*refs)` resolves refs from `AI::Tools::AbstractTool::REGISTRY`.
- Resolved tool instances are attached to chat before completion.

## Handlers

- `AI::Handlers::ConversationResponseHandler`
  - Updates message status/content.
  - Re-enters conversation sequencing with `runtime.advisor_responded(message)`.
  - Branches for compaction messages to persist compacted text/error and call `runtime.compaction_finished(message)`.
- `AI::Handlers::TurboFormFillerHandler`
  - Broadcasts success/error to Turbo Streams target.

See also: [Agents](agents.md), [Prompts](prompts.md), [Tool System](tool-system.md)
