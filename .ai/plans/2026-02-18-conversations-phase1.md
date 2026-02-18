# Plan: Conversations Phase 1 - Basic Chat Infrastructure

**Date**: 2026-02-18  
**Goal**: Minimal viable conversation feature with list, create, view, and post message capabilities

---

## Current State Assessment

**Models**: `Conversation` and `Message` models already exist with full associations and validations.

**Conversation model** (`app/models/conversation.rb`):
- `belongs_to :account`, `belongs_to :council`, `belongs_to :user`
- `has_many :messages, dependent: :destroy`
- Has `title`, `status` (active/archived enum), `last_message_at` fields
- Tenant scoped via `acts_as_tenant :account`

**Message model** (`app/models/message.rb`):
- `belongs_to :account`, `belongs_to :conversation`
- `belongs_to :sender, polymorphic: true` (User or Advisor)
- Has `content` (text), `role`, `status` fields
- Tenant scoped via `acts_as_tenant :account`

**Existing tests**: Comprehensive model tests exist for both models.

**Missing**: Controllers, routes, views for user-facing chat functionality.

---

## Goal

Enable users to:
1. Start a new conversation from a council page
2. List all conversations for a council
3. View a conversation with its messages
4. Post new messages to a conversation

## Non-goals

- Real-time updates via Turbo Streams (Phase 2)
- Close/resolve conversations (Phase 3)
- AI advisor responses (Phase 2)
- Message editing/deletion
- Message search/filtering
- File attachments

---

## Scope + Assumptions

- All account users can view all conversations in their councils
- Simple form-based message posting (no Turbo Streams for Phase 1)
- Use existing DaisyUI/Tailwind styling patterns from councils views
- Leverage existing authentication and tenant scoping patterns

---

## Implementation Steps

### Step 1: Update Routes

**File**: `config/routes.rb`

Add nested conversation routes under councils, and nested message routes under conversations:

```ruby
resources :councils do
  resources :advisors, only: [:new, :create, :edit, :update, :destroy]
  resources :conversations, only: [:index, :show, :new, :create]
end

resources :conversations do
  resources :messages, only: [:create]
end
```

### Step 2: Create ConversationsController

**File**: `app/controllers/conversations_controller.rb`

Implement:
- `index` - list conversations for a specific council (scoped to current account)
- `show` - display conversation with messages, ordered chronologically
- `new` - form to start new conversation
- `create` - create conversation with initial message

**Access control**: Use existing patterns from `CouncilsController`:
- All authenticated account users can view conversations in their councils
- No creator-only restrictions for Phase 1

**Key implementation notes**:
- Set `@council` via `Current.account.councils.find(params[:council_id])`
- For `create`, also create the first message with the conversation title as content
- Use `Current.user` as the conversation creator and first message sender

### Step 3: Create MessagesController

**File**: `app/controllers/messages_controller.rb`

Implement:
- `create` - add message to conversation

**Access control**:
- Verify user belongs to the same account as the conversation
- All account users can post to conversations in their councils

**Key implementation notes**:
- Set `@conversation` via `Current.account.conversations.find(params[:conversation_id])`
- Set `sender` to `Current.user`
- Set `role` to "user"
- After create, redirect back to conversation show page

### Step 4: Create Views

**4a. Conversation Index** (`app/views/conversations/index.html.erb`)
- Header with council name and "New Conversation" button
- List of conversations with title, status, message count, last activity
- Empty state when no conversations

**4b. Conversation Show** (`app/views/conversations/show.html.erb`)
- Header with conversation title, back link, status badge
- Message list (chronological order)
  - Current user messages: right-aligned, primary color styling
  - Other messages: left-aligned, secondary color styling
- Message form at bottom (textarea + submit)

**4c. New Conversation** (`app/views/conversations/new.html.erb`)
- Simple form with title field
- Hidden field or params for council association
- Submit creates conversation + first message

**4d. Council Show Update** (`app/views/councils/show.html.erb`)
- Add "New Conversation" button to council header
- Add "Conversations" section listing recent conversations
- Link to full conversations list

### Step 5: Add Content Validation to Message

**File**: `app/models/message.rb`

Add validation for content presence:

```ruby
validates :content, presence: true
```

### Step 6: Create/Update Tests

**6a. Update Message Model Tests** (`test/models/message_test.rb`)

Add test for content presence validation:
- `test "invalid without content"`

**6b. Create ConversationsController Tests** (`test/controllers/conversations_controller_test.rb`)

Test cases:
- `test "index shows conversations for council"`
- `test "show displays conversation with messages"`
- `test "new renders form"`
- `test "create makes conversation with first message"`
- `test "create redirects to conversation on success"`
- `test "create renders new on failure"`
- `test "redirects to sign in when not authenticated"` (for each action)

**6c. Create MessagesController Tests** (`test/controllers/messages_controller_test.rb`)

Test cases:
- `test "create adds message to conversation"`
- `test "create redirects to conversation"`
- `test "create fails with invalid content"`
- `test "redirects to sign in when not authenticated"`

**6d. Create Integration Test** (`test/integration/conversation_flow_test.rb`)

End-to-end test:
- Sign in as user
- Create a council
- Start a conversation
- Post multiple messages
- Verify messages appear in correct order

---

## Verification

Run this checklist after implementation:

- [ ] `bin/rails routes | grep conversation` shows expected routes
- [ ] Model tests pass: `bin/rails test test/models/message_test.rb`
- [ ] Controller tests pass: `bin/rails test test/controllers/conversations_controller_test.rb test/controllers/messages_controller_test.rb`
- [ ] Integration test passes: `bin/rails test test/integration/conversation_flow_test.rb`
- [ ] Manual test: Create conversation from council page
- [ ] Manual test: Post message and see it appear
- [ ] Manual test: Verify other account users can view conversation
- [ ] Verify tenant scoping: Conversation from account A not visible to account B

---

## Doc Impact

- **Updated**: `.ai/docs/features/conversations.md` (create/update)
- **Deferred**: Pattern docs (reuse existing council/advisor patterns)

---

## Rollback

If implementation fails:
1. Delete new controllers: `app/controllers/conversations_controller.rb`, `app/controllers/messages_controller.rb`
2. Delete new views: `app/views/conversations/`, `app/views/messages/`
3. Delete new tests: `test/controllers/conversations_controller_test.rb`, `test/controllers/messages_controller_test.rb`, `test/integration/conversation_flow_test.rb`
4. Revert routes.rb changes
5. Revert content validation in Message model if added
6. Revert council show view changes

---

## Unknowns / Risks

1. **Message role field**: The existing Message model requires a `role` enum. For Phase 1 user messages, use `"user"`.
2. **Conversation title**: Currently optional in DB but request asks for title validation. May need migration if title presence is required.
3. **Status enum mismatch**: Request specifies `active, resolved` but model has `active, archived`. Document which to use.
