# Conversations

Users can start conversations with AI advisors in their councils.

## Overview

Conversations are chat sessions tied to a specific space (and optionally a council). Each conversation has a title and can have multiple messages. Users can post messages and advisors respond based on the Rules of Engagement (RoE) mode. User posts update the chat in place, and advisor responses are generated asynchronously via the conversation runtime.

## Usage

### Starting a conversation
1. Navigate to a council page
2. Click "New Conversation" button in the Conversations section
3. Enter a topic/title
4. Submit to create the conversation (no seeded first message)
5. Ask the first question in chat after creation

### Posting messages
1. Open a conversation from the council page or conversation list
2. Type message in the text area at bottom
3. Click "Post Message"
4. Message appears in the chat area without a redirect (user messages on right, others on left)
5. Advisor placeholders stay hidden while `pending`; they appear only after transitioning to `responding`

### Deleting a conversation
1. Open the conversation list row actions (3-dots menu)
2. Choose "Delete" (only available to conversation starter or council creator)
3. Confirm deletion (cannot be undone)
4. Conversation and all messages are permanently deleted

### Archiving a conversation
1. Open the conversation list row actions (3-dots menu)
2. Choose "Archive"
3. Conversation status changes to archived

### Editing a title
1. Open any conversation
2. Click the pen icon in the chat header
3. Edit the title and click "Save"
4. Manual edit locks the title from future auto-title updates

## Technical

### Routes
```
/councils/:council_id/conversations     # index, new, create
/conversations/:id                        # show, update (PATCH for title/RoE), destroy
/conversations/:id/finish                 # POST - finish active council meeting (sets resolved)
/conversations/:id/archive                # POST - archive conversation
/conversations/:conversation_id/messages  # create
/conversations/:conversation_id/messages/:id/interactions # GET
/conversations/:conversation_id/messages/:id/retry        # POST
/conversations/:id/invite_advisor         # POST - add advisor to conversation
/conversations/quick_create               # POST - quick start from dashboard
```

### Models
- `Conversation`: title, status (active/resolved/archived), roe_type (open/consensus/brainstorming), conversation_type (council_meeting/adhoc), context (jsonb), space_id, council_id (nullable), user_id, scribe_initiated_count
- `Message`: content, role (user/advisor/system), status (pending/complete/error/cancelled), sender (polymorphic User/Advisor), in_reply_to_id
- `Provider`: AI provider credentials (OpenAI, OpenRouter)
- `LlmModel`: Available models per provider

### Controllers
- `ConversationsController`: index, show, new, create, update, destroy, finish, archive, invite_advisor, quick_create
- `MessagesController`: create (starts the conversation runtime + adhoc first-message auto-title job)
- `ProvidersController`: manage AI provider credentials

### Services
- `AI::Runtimes::*ConversationRuntime`: orchestrate responder selection, placeholder creation, and turn sequencing (`user_posted` / `advisor_responded`)
- `AI::Runner`: executes conversation `RespondTask` and utility `TextTask` with context/handler/tracker decomposition

### Jobs
- `AIRunnerJob`: canonical async runner for task/context/handler execution
- `GenerateConversationTitleJob`: Async title generation for adhoc conversations after the first user message

### Access Control
- All authenticated account users can view conversations in their current space
- Any account user can post to conversations in their current space
- Inaccessible councils/conversations outside `Current.space` return `404` (security-first)
- **Delete permission**: Only conversation starter or council creator can delete
- Provider management available to all account users (Phase 1)

### Styling
- DaisyUI card, btn, badge classes
- Chat bubbles: user messages (primary color, right), others (neutral, left)
- Responding and error messages update through the shared conversation stream
- Error messages show error bubble styling
- Inline actions (copy/debug/interactions) appear on hover/focus in the message footer
- Conversation and council meeting chat views share the same chat UI; only adhoc conversations show the sidebar
- Only the inner message list scrolls; chat pages avoid page-level scrolling

## Rules of Engagement

Rules of Engagement (RoE) control how advisors respond to user messages.

### Modes

| Mode | Behavior |
|------|----------|
| **Open** | Advisors respond only when @mentioned; use @all for all advisors; max depth 1 |
| **Consensus** | All advisors discuss until consensus; max depth 5 (advisors can reply to each other) |
| **Brainstorming** | All advisors iterate on ideas; max depth 2 |

### Changing RoE

Users can change RoE at any time during a conversation using the dropdown in the conversation header.

### @Mentions

Use `@advisor-name` in messages to trigger specific advisors:
- Works in all modes (overrides normal RoE behavior)
- Names are canonicalized to lowercase letters, numbers, and dashes
- Example: `@helper-bot` mentions advisor named `helper-bot`
- Mention triggers also apply inside advisor responses (including scribe): when an advisor mentions another advisor handle, the mentioned advisor is queued to respond (depth limits still apply)

### AI Response Flow

1. User posts message
2. `MessagesController` saves the user message and calls `AI.runtime_for_conversation(@conversation).user_posted(@message)`
3. New-runtime messages are marked for model-owned Turbo broadcasts on the conversation stream
4. Placeholder messages are created with `pending` status for selected responders but stay hidden
5. When a response run starts, the placeholder transitions to `responding` and is appended in chat
6. `AI::Handlers::ConversationResponseHandler` strips optional `[speaker: ...]` prefixes, persists completed/failed state, and notifies runtime sequencing
7. The `Message` model broadcasts the append/replace updates so the chat stays live without a redirect

### Adhoc Auto-title Flow

1. User posts first message in an `adhoc` conversation
2. `MessagesController` enqueues `GenerateConversationTitleJob` only when title is not manually locked
3. Job calls `AI.generate_text` with `tasks/conversation_title`
4. On success, conversation title is updated
5. On error/blank generation, title is left unchanged

### Error Handling

- API errors: Message updated with `API Error: ...` and `error` status
- Empty responses: Marked as `Empty response from AI`
- New-runtime message visibility still excludes `pending` on refresh so initial load matches live updates

### Implementation

- `roe_type` stored as string enum: `open`, `consensus`, `brainstorming`; default: `open`
- Conversation runtime classes (`OpenConversationRuntime`, `ConsensusConversationRuntime`, `BrainstormingConversationRuntime`) own RoE behavior for current message posting flow
- `AI::Tasks::RespondTask` and `AI::Client::Chat` handle chat prompt assembly and LLM execution
- Credentials encrypted with Rails encrypted attributes
- Turbo Streams provide real-time UI updates
- Delete action uses `destroy!` with authorization check
- Non-council `ConversationsController#index` redirects to the most recent adhoc conversation or auto-creates one with only Scribe

## AI Provider Setup

### Adding a Provider
1. Navigate to "AI Providers" in navigation
2. Use the 4-step wizard: Select → Authenticate → Test → Name
3. Supported types: `openai`, `openrouter`
4. API key is encrypted at rest

### Adding Models
After provider is created, navigate to provider's model management page to enable/disable models:
```
/providers/:id/models
```

### Cost Tracking
Usage records capture:
- Input/output token counts
- Provider and model used
- Calculated cost from model pricing metadata
- Associated message and conversation

## Deferred to Future Phases
- Streaming responses (currently full response only)
- Rate limiting per account
- Provider health checks and automatic failover
- Message editing/regeneration
