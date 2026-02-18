# Conversations

Users can start conversations with AI advisors in their councils.

## Overview

Conversations are chat sessions tied to a specific council. Each conversation has a title and can have multiple messages. Users can post messages and advisors respond based on the Rules of Engagement (RoE) mode. When advisors are triggered, placeholder "thinking..." messages appear until AI responses are generated (Phase 3).

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

## Technical

### Routes
```
/councils/:council_id/conversations     # index, new, create
/conversations/:id                        # show, update (PATCH for RoE)
/conversations/:conversation_id/messages  # create
```

### Models
- `Conversation`: title, status (active/archived), rules_of_engagement, context (jsonb), council_id, user_id
- `Message`: content, role (user/advisor/system), status (pending/complete/error), sender (polymorphic User/Advisor)

### Controllers
- `ConversationsController`: index, show, new, create, update
- `MessagesController`: create

### Services
- `ScribeCoordinator`: Determines which advisors should respond based on RoE mode and @mentions

### Access Control
- All authenticated account users can view all conversations in their councils
- Any account user can post to any conversation in their councils
- No creator-only restrictions (Phase 1)

### Styling
- DaisyUI card, btn, badge classes
- Chat bubbles: user messages (primary color, right), others (neutral, left)
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

### Placeholder Messages

When advisors are triggered to respond, a placeholder message appears:
- Content: "[Advisor Name] is thinking..."
- Status: `pending`
- Role: `system`
- Will be replaced with actual AI response in Phase 3

### Implementation

- Stored in `conversations.rules_of_engagement` (string enum)
- Default: `round_robin`
- State tracking (round robin position) in `conversations.context` jsonb
- `ScribeCoordinator` service determines responders

## Phase 3 (Deferred)
- Turbo Streams for real-time updates
- AI API integration for actual advisor responses
- Conversation status changes (resolve/close)
