# Conversations

Users can start conversations with AI advisors in their councils.

## Overview

Conversations are chat sessions tied to a specific council. Each conversation has a title and can have multiple messages. Users can post messages and advisors respond based on the Rules of Engagement (RoE) mode. When advisors are triggered, placeholder "thinking..." messages appear immediately, and AI responses are generated asynchronously via background jobs.

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
/conversations/:id/finish                 # Begin conclusion process
/conversations/:id/cancel_pending         # Stop pending advisor responses
```

### Models
- `Conversation`: title, status (active/archived), rules_of_engagement, context (jsonb), council_id, user_id
- `Message`: content, role (user/advisor/system), status (pending/complete/error), sender (polymorphic User/Advisor)
- `Provider`: AI provider credentials (OpenAI, Anthropic, GitHub Models)
- `LlmModel`: Available models per provider (GPT-4, Claude, etc.)

### Controllers
- `ConversationsController`: index, show, new, create, update, destroy, finish, approve_summary, reject_summary, regenerate_summary, cancel_pending
- `MessagesController`: create (enqueues AI response jobs)
- `ProvidersController`: manage AI provider credentials

### Services
- `ScribeCoordinator`: Determines which advisors should respond based on RoE mode and @mentions
- `AiClient`: Calls LLM APIs (OpenAI, Anthropic, GitHub Models) with conversation context

### Jobs
- `GenerateAdvisorResponseJob`: Async AI response generation, usage tracking, Turbo Stream broadcasts

### Access Control
- All authenticated account users can view all conversations in their councils
- Any account user can post to any conversation in their councils
- **Delete permission**: Only conversation starter or council creator can delete
- **Finish/cancel permission**: Only conversation starter or council creator can finish or cancel pending responses
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
| **Round Robin** | Advisors take turns responding in sequence |
| **Moderated** | System selects advisor with fewest messages in conversation |
| **On Demand** | Only @mentioned advisors respond |
| **Silent** | No advisor responses (user-to-user mode) |
| **Consensus** | All advisors respond (internal debate mode) |

### Changing RoE

Users can change RoE at any time during a conversation using the dropdown in the conversation header.

### @Mentions

Use `@Advisor_Name` in messages to trigger specific advisors:
- Works in all modes (overrides normal RoE behavior)
- Names are case-insensitive and use underscores for spaces
- Example: `@Helper_Bot` mentions advisor named "Helper Bot"

### AI Response Flow

1. User posts message
2. `MessagesController` calls `ScribeCoordinator` to determine responders
3. Placeholder messages created with `pending` status and "thinking..." content
4. `GenerateAdvisorResponseJob` enqueued for each responder
5. Background job:
   - Calls LLM API via `AiClient`
   - Updates placeholder with AI response and `complete` status
   - Creates `UsageRecord` with token count and cost
   - Broadcasts via Turbo Streams to update UI in real-time
6. User sees live message replacement without page refresh

### Canceling Pending Responses

Users can stop pending advisor responses if they were triggered by mistake or are no longer needed:

1. Click "Stop Responses" button (visible when pending messages exist)
2. Controller updates all `pending` messages to `cancelled` status
3. Jobs for cancelled messages are skipped when they execute
4. Only conversation starter or council creator can cancel

### Error Handling

- API errors: Message updated with error content and `error` status
- Empty responses: Marked as error with appropriate message
- All errors broadcast via Turbo Streams

### Implementation

- Stored in `conversations.rules_of_engagement` (string enum)
- Default: `round_robin`
- State tracking (round robin position) in `conversations.context` jsonb
- `ScribeCoordinator` service determines responders
- `AiClient` handles OpenAI, Anthropic, and GitHub Models APIs with tool access for advisors
- Credentials encrypted with Rails encrypted attributes
- Turbo Streams provide real-time UI updates
- Delete action uses `destroy!` with authorization check
- Cancel pending updates messages from `pending` to `cancelled` status

## AI Provider Setup

### Adding a Provider
1. Navigate to "AI Providers" in navigation
2. Click "Add Provider"
3. Enter provider name, type (OpenAI, Anthropic, GitHub Models), and API key
4. Save (API key is encrypted at rest)

### Adding Models
Providers are created with models via console/seeds (UI coming in Phase 2):
```ruby
provider = account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "sk-...")
provider.llm_models.create!(account: account, name: "GPT-4", identifier: "gpt-4")
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
