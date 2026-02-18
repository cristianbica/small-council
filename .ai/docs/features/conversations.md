# Conversations

Users can start conversations with AI advisors in their councils.

## Overview

Conversations are chat sessions tied to a specific council. Each conversation has a title and can have multiple messages. Currently, only users can post messages (advisor responses are Phase 2).

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
/conversations/:id                        # show
/conversations/:conversation_id/messages  # create
```

### Models
- `Conversation`: title, status (active/archived), council_id, user_id
- `Message`: content, role (user/advisor/system), sender (polymorphic User/Advisor)

### Controllers
- `ConversationsController`: index, show, new, create
- `MessagesController`: create

### Access Control
- All authenticated account users can view all conversations in their councils
- Any account user can post to any conversation in their councils
- No creator-only restrictions (Phase 1)

### Styling
- DaisyUI card, btn, badge classes
- Chat bubbles: user messages (primary color, right), others (neutral, left)
- Scrollable message area with max-height

## Phase 2 (Deferred)
- Turbo Streams for real-time updates
- Advisor AI responses
- Conversation status changes (resolve/close)
