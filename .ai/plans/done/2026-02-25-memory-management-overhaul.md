# Memory Management Overhaul Plan

**Date**: 2026-02-25
**Status**: Draft
**Scope**: Major architectural enhancement
**Estimated Effort**: 3-4 weeks

## Executive Summary

Transform memory from a simple text field into a structured, queryable notebook system with first-class Scribe integration, tool-based interactions, and user-editable pages.

---

## Current State

- Memory stored as raw text in `conversations.memory` and `spaces.memory`
- Scribe operates invisibly during moderated conversations
- No structured access to memory content
- Users cannot interact with Scribe outside of conversations
- No memory types or categorization

---

## Proposed Architecture

### 1. Database Schema

```ruby
# New table: memories
class CreateMemories < ActiveRecord::Migration[8.0]
  def change
    create_table :memories do |t|
      t.references :account, null: false, foreign_key: true
      t.references :space, null: false, foreign_key: true

      # Polymorphic source (optional)
      t.references :source, polymorphic: true, null: true

      # Memory metadata
      t.string :title, null: false
      t.text :content, null: false
      t.string :memory_type, null: false  # summary, conversation_summary, conversation_notes, knowledge
      t.jsonb :metadata, default: {}
      t.string :status, default: "active" # active, archived, draft

      # For page-like ordering
      t.integer :position, default: 0

      # Timestamps & tracking
      t.datetime :created_at
      t.datetime :updated_at
      t.references :created_by, polymorphic: true  # User or Advisor
      t.references :updated_by, polymorphic: true
    end

    add_index :memories, [:space_id, :memory_type]
    add_index :memories, [:space_id, :status]
    add_index :memories, :metadata, using: :gin
  end
end
```

### 2. Scribe Tool System

The Scribe becomes a tool-enabled agent that can:

**Available Tools (Scribe-only):**
- `finish_conversation(conversation_id)` - Conclude current conversation
- `update_memory(memory_id, content)` - Edit existing memory
- `create_memory(title, content, type)` - Add new memory entry
- `query_memories(query, filters)` - Search space memories
- `summarize_memories(memory_ids)` - Condense multiple memories
- `archive_memory(memory_id)` - Mark memory as archived
- `request_advisor_response(advisor_id, prompt)` - Ask specific advisor to speak
- `broadcast_message(content)` - Send message to conversation

**Available Tools (All Advisors):**
- `query_memories(query, memory_type, limit)` - Request additional memories beyond the auto-fed summary

**Tool Schema:**
```ruby
class ScribeTool
  attr_reader :name, :description, :parameters

  def execute(params, context)
    # Tool implementation
  end
end

# Example: Finish Conversation Tool
class FinishConversationTool < ScribeTool
  def initialize
    @name = "finish_conversation"
    @description = "Conclude the current conversation and generate a summary"
    @parameters = {
      conversation_id: { type: "string", required: true },
      reason: { type: "string", required: false }
    }
  end

  def execute(params, context)
    conversation = context.conversation
    lifecycle = ConversationLifecycle.new(conversation)
    lifecycle.begin_conclusion_process

    { success: true, message: "Conversation conclusion initiated" }
  end
end

# Example: Query Memories Tool (available to all advisors)
class QueryMemoriesTool < AdvisorTool
  def initialize
    @name = "query_memories"
    @description = "Search for specific memories beyond the auto-fed summary"
    @parameters = {
      query: { type: "string", required: true, description: "Search terms or question" },
      memory_type: { type: "string", required: false, enum: ["conversation_summary", "conversation_notes", "knowledge", "summary"] },
      limit: { type: "integer", required: false, default: 5 }
    }
  end

  def execute(params, context)
    scope = context.space.memories.where(status: "active")
    scope = scope.where(memory_type: params[:memory_type]) if params[:memory_type].present?
    scope = scope.where("title ILIKE ? OR content ILIKE ?", "%#{params[:query]}%", "%#{params[:query]}%")

    memories = scope.order(updated_at: :desc).limit(params[:limit] || 5)

    {
      success: true,
      count: memories.size,
      memories: memories.map { |m| { id: m.id, title: m.title, type: m.memory_type, content: m.content.truncate(500) } }
    }
  end
end
```

### 3. Scribe Chat Interface

**New Route**: `/spaces/:space_id/scribe`

**Interface Components:**
- Chat-like message stream between user and Scribe
- Scribe can suggest tools with "click to execute" buttons
- Memory browser sidebar (searchable, filterable)
- Quick actions: "Summarize recent conversations", "Find related memories", "Create decision record"

**Sample Interactions:**
```
User: "Summarize what we decided about the API last week"
Scribe: [queries memories] "Based on 3 conversations from last week:
- REST API chosen over GraphQL (Feb 20)
- Authentication will use JWT tokens (Feb 21)
- Rate limiting set to 1000 req/min (Feb 22)
Would you like me to create a consolidated decision document?"

User: "Yes, and finish the current conversation"
Scribe: [suggests tools: create_memory + finish_conversation]
```

**Advisor Memory Query Example:**
```
Backend Advisor: "I need to see our previous API decisions to give informed advice"
[uses query_memories tool with query="API authentication decision"]
System: Returns 2 matching memories
Backend Advisor: "Based on the JWT decision record from Feb 21, I recommend..."
```

### 4. Memory Types

| Type | Description | Source | Auto-Fed to Agents | Example |
|------|-------------|--------|-------------------|---------|
| `summary` | Main space memory - cumulative knowledge | Conversation or Manual | ✅ Yes | "Space purpose, key decisions, ongoing projects" |
| `conversation_summary` | Post-conversation recap | Conversation | ❌ No | "Team agreed to use Kubernetes..." |
| `conversation_notes` | Detailed discussion notes | Conversation | ❌ No | "Key points raised during debate..." |
| `knowledge` | Space knowledge base entries | Manual or Scribe | ❌ No | "Our deployment process is..." |

**Type Details:**

- **`summary`**: The primary space memory that accumulates over time. Updated after conversations or manually. **This is the only memory type automatically included in AI agent context.**
- **`conversation_summary`**: High-level takeaway from a specific conversation. Always linked to source conversation. Not auto-fed, but agents can query for it when needed.
- **`conversation_notes`**: Detailed capture of discussion points, alternatives considered, debate points. Linked to source. Not auto-fed (too verbose), but searchable on-demand.
- **`knowledge`**: Standalone knowledge entries about the space, processes, standards. Not auto-fed, but agents can reference or request these explicitly.

**Context Feeding Rules:**
```ruby
# In AIClient#build_memory_context
# ONLY the summary memory is auto-fed
# Other memories must be explicitly queried

def load_memories_for_context
  # Auto-feed: only the primary summary memory
  summary_memory = space.memories
    .where(status: "active")
    .where(memory_type: "summary")
    .order(updated_at: :desc)
    .first

  # Return just the summary content (or empty if none)
  summary_memory&.content.to_s
end

def query_memories(query:, filters: {})
  # On-demand query for advisors to request specific memories
  scope = space.memories.where(status: "active")

  scope = scope.where(memory_type: filters[:type]) if filters[:type].present?
  scope = scope.where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")

  scope.order(updated_at: :desc).limit(filters[:limit] || 5)
end
```

**Advisor Memory Access:**

Advisors can request additional memories via a tool call:
```ruby
# Tool available to all advisors
class QueryMemoriesTool < AdvisorTool
  def execute(query:, memory_type: nil, limit: 5)
    memories = query_memories(
      query: query,
      filters: { type: memory_type, limit: limit }
    )

    memories.map { |m| { id: m.id, title: m.title, type: m.memory_type, content: m.content } }
  end
end
```

### 5. UI/UX Design

**Memory Page (`/spaces/:space_id/memory`)**:
```
┌─────────────────────────────────────────────────────────┐
│ Space Memory                    [+ New Memory] [Search]  │
├──────────────┬──────────────────────────────────────────┤
│              │                                          │
│ Filters      │  📄 Deployment Decisions                 │
│ ─────────    │  Type: decision | Created: Feb 20, 2026  │
│ ☑️ All       │                                          │
│ ☐ Summary    │  We decided to use Kubernetes for...     │
│ ☐ Meeting    │                                          │
│ ☐ Decision   │  [Edit] [Archive] [Ask Scribe]            │
│              │                                          │
│ ─────────    │  📄 API Authentication Discussion        │
│ Tags         │  Type: conversation_summary              │
│ [api] [auth] │  Source: Conversation #123               │
│              │                                          │
│ [Ask Scribe] │  JWT tokens chosen over session...        │
│              │                                          │
└──────────────┴──────────────────────────────────────────┘
```

**Scribe Chat Modal**:
```
┌─────────────────────────────────────┐
│ Chat with Scribe              [×]  │
├─────────────────────────────────────┤
│                                     │
│ Scribe: How can I help you manage   │
│ your space memory today?           │
│                                     │
│ [Summarize recent conversations]   │
│ [Find related memories]             │
│ [Create decision record]            │
│                                     │
│ ─────────────────────────────────── │
│                                     │
│ You: What did we decide about the  │
│ database?                           │
│                                     │
│ Scribe: [searches] I found 2       │
│ related memories:                  │
│ • "Database Decision" (Feb 15)     │
│ • "Migration Planning" (Feb 18)     │
│                                     │
│ Key point: PostgreSQL chosen over  │
│ MySQL for ACID compliance...        │
│                                     │
│ [Type your message...]    [Send]   │
└─────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- Create `memories` table migration
- Build `Memory` model with validations
- Implement basic CRUD controller (`MemoriesController`)
- Create memory index/show views
- Write tests for model and controller

**Files to create:**
- `db/migrate/xxx_create_memories.rb`
- `app/models/memory.rb`
- `app/controllers/memories_controller.rb`
- `app/views/memories/index.html.erb`
- `app/views/memories/show.html.erb`
- `app/views/memories/_form.html.erb`
- `test/models/memory_test.rb`
- `test/controllers/memories_controller_test.rb`

### Phase 2: Scribe Tool Framework (Week 1-2)
- Build `ScribeTool` and `AdvisorTool` base classes
- Implement first 3 Scribe tools: finish_conversation, create_memory, query_memories
- Implement `QueryMemoriesTool` available to all advisors for on-demand memory access
- Create tool execution framework
- Add tool suggestion UI in conversation view
- Write service tests

**Files to create:**
- `app/services/scribe_tool.rb`
- `app/services/advisor_tool.rb`
- `app/services/scribe_tools/finish_conversation_tool.rb`
- `app/services/scribe_tools/create_memory_tool.rb`
- `app/services/scribe_tools/query_memories_tool.rb`
- `app/services/advisor_tools/query_memories_tool.rb`
- `app/services/scribe_tool_executor.rb`

### Phase 3: Scribe Chat Interface (Week 2)
- Build chat UI components
- Create chat message model (or use Memory with type: chat)
- Implement real-time chat updates (Turbo Streams)
- Add memory browser sidebar
- Write controller and integration tests

**Files to create:**
- `app/controllers/space_scribe_controller.rb`
- `app/views/space_scribe/show.html.erb`
- `app/views/space_scribe/_chat.html.erb`
- `app/views/space_scribe/_memory_browser.html.erb`
- `app/javascript/controllers/scribe_chat_controller.js`

### Phase 4: Migration & Integration (Week 3)
- Migrate existing `spaces.memory` text to `memories` table
- Update `ConversationLifecycle` to create Memory records instead of JSON
- Modify `GenerateConversationSummaryJob` to save to memories table
- Update AI context building to query memories table
- Write migration tests

**Files to modify:**
- `app/models/space.rb` (add has_many :memories)
- `app/services/conversation_lifecycle.rb`
- `app/jobs/generate_conversation_summary_job.rb`
- `app/services/ai_client.rb` (memory context building)

### Phase 5: Advanced Features (Week 4)
- Memory search with filters
- Memory tagging system
- Memory relationships (linked memories)
- Export memories (PDF, Markdown)
- Memory templates (decision record template, etc.)

**Files to create:**
- `app/services/memory_search.rb`
- `app/views/memories/search.html.erb`
- Memory export functionality

---

## Acceptance Criteria

1. **Database**: Memories table exists with all specified columns and indexes
2. **Scribe Tools**: At least 3 tools working end-to-end
3. **Chat Interface**: Users can have structured conversations with Scribe
4. **Memory CRUD**: Users can create, edit, view, and archive memories
5. **Migration**: Existing space memories migrated to `summary` type
6. **Integration**: Conversation summaries saved as `conversation_summary` records; detailed notes as `conversation_notes` (neither auto-fed)
7. **Context Feeding**: Only `summary` type is automatically fed to AI agents; advisors can query for other memories on-demand
8. **Tests**: 90%+ coverage on new code
9. **UX**: Memory page is primary navigation destination

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Scribe tool execution errors | Wrap in transactions, provide rollback UI |
| Large memory content | Paginate, lazy load, truncate in previews |
| Migration data loss | Full backup, dry-run migration, verification script |
| Tool abuse | Rate limiting, permission checks, audit logging |
| UX complexity | Progressive disclosure, tooltips, onboarding tour |

---

## Documentation Tasks

- [ ] Update `.ai/docs/features/memory-management.md` (new)
- [ ] Update `.ai/MEMORY.md` with new commands
- [ ] Create Scribe tool usage guide
- [ ] Write migration runbook
- [ ] Document memory API for AI context

---

## Next Steps

1. Review plan with stakeholders
2. Create Phase 1 sub-tasks
3. Begin database migration development
4. Set up feature branch: `feature/memory-management`

---

## Appendix: Sample Memory Record

```json
{
  "id": 123,
  "account_id": 1,
  "space_id": 5,
  "source_type": "Conversation",
  "source_id": 45,
  "title": "API Authentication Architecture Decision",
  "content": "After discussion with Security Advisor and Backend Advisor, we decided:\n\n**Decision**: Use JWT tokens with refresh token rotation\n\n**Rationale**:\n- Stateless authentication scales better\n- Refresh tokens allow session management\n- Industry standard with good library support\n\n**Implementation Notes**:\n- 15-minute access token expiry\n- 7-day refresh token expiry\n- Store tokens in httpOnly cookies\n\n**Follow-up**: Backend Advisor will create implementation ticket.",
  "memory_type": "knowledge",
  "metadata": {
    "decision_date": "2026-02-25",
    "deciders": ["Security Advisor", "Backend Advisor"],
    "confidence": "high",
    "alternatives_considered": ["Session cookies", "OAuth2"],
    "tags": ["api", "auth", "security"],
    "access_pattern": "on_demand"
  },
  "status": "active",
  "position": 1,
  "created_by_type": "User",
  "created_by_id": 3,
  "updated_at": "2026-02-25T14:30:00Z"
}
```
