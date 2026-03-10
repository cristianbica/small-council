# Tool System

RubyLLM-native tool framework for agent tasks.

## Overview

Tools now inherit directly from `AI::Tools::AbstractTool` (a `RubyLLM::Tool` subclass). The old `BaseTool` and adapter layer were removed.

## Architecture

```
app/libs/ai/tools/
├── abstract_tool.rb
├── advisors/
│   ├── create_advisor_tool.rb
│   ├── fetch_advisor_tool.rb
│   ├── list_advisors_tool.rb
│   └── update_advisor_tool.rb
├── internet/
│   └── browse_web_tool.rb
└── memories/
    ├── create_memory_tool.rb
    ├── fetch_memory_tool.rb
    ├── list_memories_tool.rb
    ├── search_memories_tool.rb
    └── update_memory_tool.rb
```

## Registry + Resolution

- `AI::Tools::AbstractTool::REGISTRY` maps tool refs to class names.
- `AI.tool` / `AI.tools` resolve and load tool classes.
- `AI::Tasks::BaseTask#register_tools` instantiates tool classes with task context and attaches them to `AI::Client::Chat`.

## Runtime Wiring

- Tool access is declared by agents (for example `AdvisorAgent#tools`).
- Conversation runtime execution goes through `AI::Runner` task/context/handler flow.
- Tool traces are captured by trackers and mirrored to `messages.tool_calls`.
