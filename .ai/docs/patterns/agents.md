# Agents

How AI agents are implemented and selected by tasks.

## Overview

Agents are lightweight policy objects under `app/libs/ai/agents/`.

- `AI::Agents::BaseAgent` defines shared behavior (system prompt loading and optional tool overrides).
- `AI::Agents::AdvisorAgent` drives conversation replies.
- `AI::Agents::TextWriterAgent` drives utility text-generation tasks.

Tasks select their agent via `self.agent = ...` and instantiate it through `AI.agent(...)`.

## Implemented Classes

- `app/libs/ai/agents/base_agent.rb`
  - `self.system_prompt = "..."` declares the prompt key.
  - `#system_prompt` resolves ERB prompt content through `AI.prompt(...)`.
  - `tools` can be injected at initialization time.
- `app/libs/ai/agents/advisor_agent.rb`
  - `self.system_prompt = "agents/advisor"`.
  - Tool policy:
    - explicit injected tools win
    - default is `"memories/*"` only when `context.scribe?`
    - otherwise no tools.
- `app/libs/ai/agents/text_writer_agent.rb`
  - `self.system_prompt = "agents/text_writer"`.

## How Tasks Use Agents

- `app/libs/ai/tasks/respond_task.rb`
  - `self.agent = :advisor`
  - Uses `agent.system_prompt` and appends optional runtime prompt (`@prompt`) when provided.
- `app/libs/ai/tasks/text_task.rb`
  - `self.agent = :text_writer`
  - Uses `agent.system_prompt` plus a task-specific user prompt.

The task base class wires this in `app/libs/ai/tasks/base_task.rb`:

- Instantiates the task agent with `AI.agent(self.class.agent)`.
- Reads `agent.tools` and resolves classes through `AI.tools(*refs)`.
- Registers resolved tools on the chat session before completion.

## Where Agent Runs Start

- Conversation responses: `AI.generate_advisor_response(...)` in `app/libs/ai.rb`
- Utility generation: `AI.generate_text(...)` in `app/libs/ai.rb`
- Generic entrypoint: `AI.run(...)` in `app/libs/ai.rb`

See also: [Tasks](tasks.md), [Prompts](prompts.md), [Tool System](tool-system.md)
