# Conversations

Users can start conversations with AI advisors in their councils.

## Overview

Conversations are chat sessions tied to a specific space (and optionally a council). Each conversation has a title and can have multiple messages. Users can post messages and advisors respond based on the Rules of Engagement (RoE) mode. When advisors are triggered, placeholder "thinking..." messages appear immediately, and AI responses are generated asynchronously via background jobs.

## Usage

### Starting a conversation
1. Navigate to a council page
2. Click "New Conversation" button in the Conversations section
3. Enter a topic/title
4. Submit to create conversation and first message

### Posting messages
1. Open a conversation from the council page or conversation list
2. Type message in the text area at bottom
3. Click "Post Message"
4. Message appears in the chat area (user messages on right, others on left)
5. AI advisors generate responses asynchronously; placeholders show "thinking..."

### Deleting a conversation
1. Open the conversation or view it in the conversation list
2. Click "Delete" button (only visible to conversation starter or council creator)
3. Confirm deletion (cannot be undone)
4. Conversation and all messages are permanently deleted

## Technical

### Routes
```
/councils/:council_id/conversations     # index, new, create
/conversations/:id                        # show, update (PATCH for RoE), destroy
/conversations/:conversation_id/messages  # create
/conversations/:id/invite_advisor         # POST - add advisor to conversation
/conversations/quick_create               # POST - quick start from dashboard
```

### Models
- `Conversation`: title, status (active/concluding/resolved/archived), roe_type (open/consensus/brainstorming), conversation_type (council_meeting/adhoc), context (jsonb), space_id, council_id (nullable), user_id, scribe_initiated_count
- `Message`: content, role (user/advisor/system), status (pending/complete/error/cancelled), sender (polymorphic User/Advisor), in_reply_to_id
- `Provider`: AI provider credentials (OpenAI, OpenRouter)
- `LlmModel`: Available models per provider

### Controllers
- `ConversationsController`: index, show, new, create, update, destroy, invite_advisor, quick_create
- `MessagesController`: create (enqueues AI response jobs)
- `ProvidersController`: manage AI provider credentials

### Services
- `ConversationLifecycle`: Orchestrates message flow, advisor responses, and conversation conclusion
- `AI::ContentGenerator`: Calls LLM APIs via `AI::Client` instance with conversation context

### Jobs
- `GenerateAdvisorResponseJob`: Async AI response generation, usage tracking, Turbo Stream broadcasts

### Access Control
- All authenticated account users can view conversations in their current space
- Any account user can post to conversations in their current space
- **Delete permission**: Only conversation starter or council creator can delete
- Provider management available to all account users (Phase 1)

### Styling
- DaisyUI card, btn, badge classes
- Chat bubbles: user messages (primary color, right), others (neutral, left)
- Pending messages show pulse animation and "thinking..." badge
- Error messages show red background with error badge
- Scrollable message area with max-height

## Rules of Engagement

Rules of Engagement (RoE) control how advisors respond to user messages.

### Modes

| Mode | Behavior |
|------|----------|
| **Open** | Advisors respond only when @mentioned; use @all for all advisors; max depth 1 |
| **Consensus** | All advisors discuss until consensus; max depth 2 (advisors can reply to each other) |
| **Brainstorming** | All advisors iterate on ideas; max depth 2 |

### Changing RoE

Users can change RoE at any time during a conversation using the dropdown in the conversation header.

### @Mentions

Use `@Advisor_Name` in messages to trigger specific advisors:
- Works in all modes (overrides normal RoE behavior)
- Names are case-insensitive and use underscores for spaces
- Example: `@Helper_Bot` mentions advisor named "Helper Bot"

### AI Response Flow

1. User posts message
2. `MessagesController` calls `ConversationLifecycle#user_posted_message`
3. Placeholder messages created with `pending` status
4. `GenerateAdvisorResponseJob` enqueued for each responder
5. Background job:
   - Calls `AI::ContentGenerator#generate_advisor_response`
   - Updates placeholder with AI response and `complete` status
   - Creates `UsageRecord` (auto-tracked inside `AI::Client#chat`)
   - Calls `ConversationLifecycle#advisor_responded` for follow-up logic
   - Broadcasts via Turbo Streams to update UI in real-time
6. User sees live message replacement without page refresh

### Error Handling

- API errors: Message updated with error content and `error` status
- Empty responses: Marked as error with appropriate message
- All errors broadcast via Turbo Streams

### Implementation

- `roe_type` stored as string enum: `open`, `consensus`, `brainstorming`; default: `open`
- `ConversationLifecycle` service handles all RoE logic, advisor triggering, depth control
- `AI::ContentGenerator` handles prompt building; `AI::Client` handles LLM call + usage tracking
- Credentials encrypted with Rails encrypted attributes
- Turbo Streams provide real-time UI updates
- Delete action uses `destroy!` with authorization check

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
- Calculated cost (placeholder rates; per-model pricing in Phase 2)
- Associated message and conversation

## Deferred to Future Phases
- Streaming responses (currently full response only)
- Rate limiting per account
- Provider health checks and automatic failover
- Message editing/regeneration
