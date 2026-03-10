# Plan: RubyLLM-Native Tools Refactor

Date: 2026-03-08
Status: approved
Change type: refactor
Scope: AI tools and tool resolution only

## Goal

Replace the current adapter-based tool path with RubyLLM-native tools, using the exact RubyLLM DSL.

## Decisions

- Inherit from `RubyLLM::Tool`, use its DSL (`description`, `params do`, `execute`).
- `AI::Tools::AbstractTool::REGISTRY` is an explicit frozen hash mapping app refs to class name strings.
- `AI.tool(ref)` returns a class; caller instantiates with `klass.new(context)`.
- `AI.tools(*refs)` uses `filter_map` for clean wildcard matching.
- `AI::Client` unchanged; only `AI::Client::Chat` gets native tool path.
- Keep legacy tools and adapter in place. No removals in this slice.

## Pattern

```ruby
# AbstractTool
class AbstractTool < RubyLLM::Tool
  REGISTRY = { "memories/create" => "AI::Tools::Memories::CreateMemoryTool" }.freeze
  class_attribute :requires_approval, default: false
  class_attribute :read_only, default: false
  attr_reader :context
  def initialize(context); @context = context; end
end

# Concrete tool
class CreateMemoryTool < AbstractTool
  self.requires_approval = true
  self.read_only = false
  description "Create a memory"
  params do
    string :title, required: true
    string :memory_type, enum: Memory::MEMORY_TYPES  # runtime eval
  end
  def execute(title:, memory_type: "knowledge"); ...; end
end

# API
AI.tool("memories/create") # => class
AI.tools("memories/*")     # => [class, class]
```

## Mapping table

| Current path | Current class | Disposition | New path | New class | App ref | read_only | requires_approval |
|---|---|---|---|---|---|---:|---:|
| `app/libs/ai/tools/internal/create_memory_tool.rb` | `AI::Tools::Internal::CreateMemoryTool` | migrate now | `app/libs/ai/tools/memories/create_memory_tool.rb` | `AI::Tools::Memories::CreateMemoryTool` | `memories/create` | no | yes |
| `app/libs/ai/tools/internal/list_memories_tool.rb` | `AI::Tools::Internal::ListMemoriesTool` | migrate now | `app/libs/ai/tools/memories/list_memories_tool.rb` | `AI::Tools::Memories::ListMemoriesTool` | `memories/list` | yes | no |
| `app/libs/ai/tools/internal/read_memory_tool.rb` | `AI::Tools::Internal::ReadMemoryTool` | migrate now | `app/libs/ai/tools/memories/fetch_memory_tool.rb` | `AI::Tools::Memories::FetchMemoryTool` | `memories/fetch` | yes | no |
| `app/libs/ai/tools/internal/query_memories_tool.rb` | `AI::Tools::Internal::QueryMemoriesTool` | migrate now | `app/libs/ai/tools/memories/search_memories_tool.rb` | `AI::Tools::Memories::SearchMemoriesTool` | `memories/search` | yes | no |
| `app/libs/ai/tools/internal/update_memory_tool.rb` | `AI::Tools::Internal::UpdateMemoryTool` | migrate now | `app/libs/ai/tools/memories/update_memory_tool.rb` | `AI::Tools::Memories::UpdateMemoryTool` | `memories/update` | no | yes |
| `app/libs/ai/tools/internal/list_conversations_tool.rb` | `AI::Tools::Internal::ListConversationsTool` | migrate now | `app/libs/ai/tools/conversations/list_conversations_tool.rb` | `AI::Tools::Conversations::ListConversationsTool` | `conversations/list` | yes | no |
| `app/libs/ai/tools/internal/read_conversation_tool.rb` | `AI::Tools::Internal::ReadConversationTool` | migrate now | `app/libs/ai/tools/conversations/fetch_conversation_tool.rb` | `AI::Tools::Conversations::FetchConversationTool` | `conversations/fetch` | yes | no |
| `app/libs/ai/tools/internal/query_conversations_tool.rb` | `AI::Tools::Internal::QueryConversationsTool` | migrate now | `app/libs/ai/tools/conversations/search_conversations_tool.rb` | `AI::Tools::Conversations::SearchConversationsTool` | `conversations/search` | yes | no |
| `app/libs/ai/tools/internal/get_conversation_summary_tool.rb` | `AI::Tools::Internal::GetConversationSummaryTool` | deferred | — | — | — | — | — |
| `app/libs/ai/tools/conversations/ask_advisor_tool.rb` | `AI::Tools::Conversations::AskAdvisorTool` | deferred | — | — | — | — | — |
| `app/libs/ai/tools/internal/create_advisor_tool.rb` | `AI::Tools::Internal::CreateAdvisorTool` | migrate now | `app/libs/ai/tools/advisors/create_advisor_tool.rb` | `AI::Tools::Advisors::CreateAdvisorTool` | `advisors/create` | no | yes |
| `app/libs/ai/tools/internal/list_advisors_tool.rb` | `AI::Tools::Internal::ListAdvisorsTool` | migrate now | `app/libs/ai/tools/advisors/list_advisors_tool.rb` | `AI::Tools::Advisors::ListAdvisorsTool` | `advisors/list` | yes | no |
| `app/libs/ai/tools/internal/get_advisor_tool.rb` | `AI::Tools::Internal::GetAdvisorTool` | migrate now | `app/libs/ai/tools/advisors/fetch_advisor_tool.rb` | `AI::Tools::Advisors::FetchAdvisorTool` | `advisors/fetch` | yes | no |
| `app/libs/ai/tools/internal/update_advisor_tool.rb` | `AI::Tools::Internal::UpdateAdvisorTool` | migrate now | `app/libs/ai/tools/advisors/update_advisor_tool.rb` | `AI::Tools::Advisors::UpdateAdvisorTool` | `advisors/update` | no | yes |
| `app/libs/ai/tools/internal/create_council_tool.rb` | `AI::Tools::Internal::CreateCouncilTool` | migrate now | `app/libs/ai/tools/councils/create_council_tool.rb` | `AI::Tools::Councils::CreateCouncilTool` | `councils/create` | no | yes |
| `app/libs/ai/tools/internal/list_councils_tool.rb` | `AI::Tools::Internal::ListCouncilsTool` | migrate now | `app/libs/ai/tools/councils/list_councils_tool.rb` | `AI::Tools::Councils::ListCouncilsTool` | `councils/list` | yes | no |
| `app/libs/ai/tools/internal/get_council_tool.rb` | `AI::Tools::Internal::GetCouncilTool` | migrate now | `app/libs/ai/tools/councils/fetch_council_tool.rb` | `AI::Tools::Councils::FetchCouncilTool` | `councils/fetch` | yes | no |
| `app/libs/ai/tools/internal/update_council_tool.rb` | `AI::Tools::Internal::UpdateCouncilTool` | migrate now | `app/libs/ai/tools/councils/update_council_tool.rb` | `AI::Tools::Councils::UpdateCouncilTool` | `councils/update` | no | yes |
| `app/libs/ai/tools/internal/assign_advisor_to_council_tool.rb` | `AI::Tools::Internal::AssignAdvisorToCouncilTool` | migrate now | `app/libs/ai/tools/councils/add_advisor_tool.rb` | `AI::Tools::Councils::AddAdvisorTool` | `councils/add_advisor` | no | yes |
| `app/libs/ai/tools/internal/unassign_advisor_from_council_tool.rb` | `AI::Tools::Internal::UnassignAdvisorFromCouncilTool` | migrate now | `app/libs/ai/tools/councils/remove_advisor_tool.rb` | `AI::Tools::Councils::RemoveAdvisorTool` | `councils/remove_advisor` | no | yes |
| `app/libs/ai/tools/external/browse_web_tool.rb` | `AI::Tools::External::BrowseWebTool` | migrate now | `app/libs/ai/tools/internet/browse_web_tool.rb` | `AI::Tools::Internet::BrowseWebTool` | `internet/browse_web` | yes | no |

## Implementation steps

1. Add `AI::Tools::AbstractTool` inheriting from `RubyLLM::Tool` with `REGISTRY`, `class_attribute` metadata, and required `context` initialization.
2. Add `AI.tool(ref)` that returns class via `safe_constantize`, raising `ResolutionError`.
3. Add `AI.tools(*refs)` using `filter_map` for wildcard matching.
4. Create new folders under `app/libs/ai/tools/` for each domain.
5. Implement native tools for all `migrate now` entries using RubyLLM DSL.
6. Wire native tools into `AI::Client::Chat` only.

## Acceptance criteria

- `AbstractTool` exists with `REGISTRY`, metadata, context init.
- `AI.tool` and `AI.tools` work as specified.
- All `migrate now` tools exist in new structure.
- No changes to `AI::Client`.
- Legacy tools remain in place.

## Verification

- Unit test `AI.tool` returns correct class.
- Unit test `AI.tools` with wildcards.
- Unit test metadata inheritance.
- Run tests for migrated tools.

## Out of scope

- Changes to `AI::Client`.
- Advisor/Participant permission model.
- Tool approval UI.
- Legacy tool removal.
- Renaming `AbstractTool` to `BaseTool`.
