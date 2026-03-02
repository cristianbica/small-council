# Memory Management

## Overview

The memory management system transforms raw conversation text into a structured, queryable knowledge base. Memories are the primary mechanism for accumulating and organizing space knowledge.

## Memory Types

| Type | Description | Source | Auto-Fed to AI |
|------|-------------|--------|----------------|
| `summary` | Primary space overview - cumulative knowledge | Manual or Scribe | ✅ Yes |
| `conversation_summary` | Key takeaways from a specific conversation | Manual or tool-created | ❌ No |
| `conversation_notes` | Detailed discussion notes | Manual or tool-created | ❌ No |
| `knowledge` | Standalone knowledge entries | Manual or Scribe | ❌ No |

### Key Rule

**Only `summary` memory type is automatically fed to AI agents.** All other types must be queried on-demand using the `query_memories` tool.

## Architecture

### Database Schema

```ruby
# memories table
t.references :account, null: false  # Multi-tenancy
t.references :space, null: false   # Belongs to space
t.references :source, polymorphic: true  # Optional: linked to conversation
t.string :title, null: false
t.text :content, null: false
t.string :memory_type, null: false  # summary, conversation_summary, conversation_notes, knowledge
t.jsonb :metadata, default: {}
t.string :status, default: "active"  # active, archived, draft
t.integer :position, default: 0
t.references :created_by, polymorphic: true  # User or Advisor
t.references :updated_by, polymorphic: true
```

### Key Components

1. **Memory Model** (`app/models/memory.rb`)
   - Validations, scopes, and business logic
   - Type and status predicates
   - Class methods for creating typed memories

2. **MemoriesController** (`app/controllers/memories_controller.rb`)
   - Full CRUD operations
   - Archive/activate actions
   - Search functionality
   - Export (Markdown, JSON)

3. **Tool System** (`app/libs/ai/tools/`)
   - Tools inherit from `AI::Tools::BaseTool`
   - `AI::Tools::Internal::QueryMemoriesTool` - Search memories (all agents)
   - `AI::Tools::Internal::CreateMemoryTool` - Create memory entries (Scribe only)
   - `AI::Tools::Internal::ReadMemoryTool` - Read specific memory
   - `AI::Tools::Internal::UpdateMemoryTool` - Edit memory entry
   - `AI::Tools::Internal::ListMemoriesTool` - List memories in space

4. **Available Tools**
  - `create_memory` - Add new memory entry (Scribe)
  - `update_memory` - Edit existing memory (Scribe)
  - `list_memories` - List memories in current space
  - `read_memory` - Read specific memory
  - `query_memories` - Search memories (all advisors)

## Usage

### Creating Memories

```ruby
# Create a summary memory (auto-fed to AI)
Memory.create_primary_summary!(
  space: space,
  title: "Space Overview",
  content: "Our architecture decisions...",
  creator: current_user
)

# Create conversation memory (not auto-fed)
Memory.create_conversation_summary!(
  conversation: conversation,
  title: "API Discussion",
  content: summary_content,
  creator: scribe_advisor
)
```

### Querying Memories

```ruby
# Get primary summary for AI context
summary = Memory.primary_summary_for(space)

# Search memories (model scope)
memories = space.memories.active.by_type("knowledge").where("content ILIKE ?", "%API%")

# Quick search via controller
GET /spaces/:space_id/memories/search?q=authentication
```

### In Conversation Context

Agents query memories via tools (not direct method calls):

```ruby
# In tool execution (AI::Tools::Internal::QueryMemoriesTool)
# context = { space: space, conversation: conversation, advisor: advisor }
# params = { "query" => "JWT authentication decision", "memory_type" => "knowledge", "limit" => 3 }
result = tool.execute(params, context)
# => { success: true, memories: [{ id: 1, title: "...", preview: "..." }, ...] }
```

## Memory Context in AI

The context builder (`AI::ContextBuilders::ConversationContextBuilder`) **only includes the summary memory**:

```ruby
# In context builder — only primary summary is injected automatically
def build_memory_context
  summary_memory = Memory.primary_summary_for(space)
  if summary_memory
    context_parts << "## Space Knowledge & Decisions"
    context_parts << summary_memory.content
  end
  # Note: Other memory types are NOT auto-fed; advisors query them via tools
end
```

This ensures:
- Context stays manageable in size
- Only relevant cumulative knowledge is included
- Advisors can query specific memories when needed

## Notes

- The dedicated auto-conclusion summary pipeline was removed from conversation finishing flow.
- `conversation_summary` entries are still supported as memory types and can be created manually or via tools/services.

## Testing

Run memory-related tests:
```bash
bin/rails test test/models/memory_test.rb
bin/rails test test/controllers/memories_controller_test.rb
```

## Routes

```
GET    /spaces/:space_id/memories           -> index
GET    /spaces/:space_id/memories/new         -> new
POST   /spaces/:space_id/memories           -> create
GET    /spaces/:space_id/memories/:id         -> show
GET    /spaces/:space_id/memories/:id/edit    -> edit
PATCH  /spaces/:space_id/memories/:id         -> update
DELETE /spaces/:space_id/memories/:id         -> destroy
POST   /spaces/:space_id/memories/:id/archive -> archive
POST   /spaces/:space_id/memories/:id/activate -> activate
GET    /spaces/:space_id/memories/search      -> search
GET    /spaces/:space_id/memories/export      -> export
```

## Future Enhancements

- Memory tagging system
- Memory relationships (linked memories)
- Full-text search with PostgreSQL tsvector
- Memory templates (decision records, ADRs)
- Automatic memory consolidation
