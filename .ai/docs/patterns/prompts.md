# Prompts

How prompt files are resolved and consumed by tasks and agents.

## Resolution

`AI.prompt(type, **locals)` (in `app/libs/ai.rb`) resolves prompts from:

- `app/libs/ai/prompts/#{type}.erb`

Behavior:

- Renders prompt as ERB using `result_with_hash(locals)`.
- Raises `AI::ResolutionError` when the file does not exist.

## Prompt Layout

Current prompt groups:

- `app/libs/ai/prompts/agents/*.erb`
- `app/libs/ai/prompts/tasks/*.erb`
- `app/libs/ai/prompts/conversations/*.erb`

Naming convention in code is path-like keys without extension, for example:

- `agents/advisor`
- `agents/text_writer`
- `tasks/advisor_profile`
- `conversations/title_generator`

## Agent Prompt Usage

`AI::Agents::BaseAgent#system_prompt` loads the agent prompt key declared on the class.

- `AI::Agents::AdvisorAgent` -> `agents/advisor`
- `AI::Agents::TextWriterAgent` -> `agents/text_writer`

Prompt locals for agent prompts include `context:`.

## Task Prompt Usage

- `AI::Tasks::TextTask`:
  - Renders `AI.prompt(@configured_prompt, context: context, task: self)`
  - Adds output as a user message (`chat.add_message content: prompt`)
- `AI::Tasks::RespondTask`:
  - Uses the advisor system prompt as base
  - Optionally appends a conversation prompt (`AI.prompt(@prompt, context: context)`) when runtime passes `prompt:`.

## Runtime and API Examples

- Conversation title generation passes `conversations/title_generator` from `app/models/conversation.rb` through `AI.run(...)`.
- Form fillers pass `tasks/advisor_profile` and `tasks/council_profile` from `app/controllers/form_fillers_controller.rb` through `AI.generate_text(...)`.
- Conversation runtimes pass conversation-level prompt keys like `conversations/consensus_moderator` through `AI.generate_advisor_response(...)` (see `app/libs/ai/runtimes/conversation_runtime.rb`).

See also: [Agents](agents.md), [Tasks](tasks.md)
