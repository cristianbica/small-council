# Conversation System Architecture

## Overview

The conversation system supports two types of conversations:

1. **Council Meeting**: Traditional conversations tied to a council with preset advisors
2. **Adhoc**: Direct conversations with any advisor outside council structure

Both types share the same underlying mechanics but differ in how they're created and managed.

## Key Features

### Universal Scribe Presence
- The Scribe (using `is_scribe` flag) is automatically present in ALL conversations
- Scribe role handled through `conversation_participants` join table
- Scribe can initiate follow-ups when messages are "solved" (all pending advisors responded)
- **Scribe follow-ups only fire for `council_meeting` conversations that are `active`** — adhoc, resolved, and archived conversations are skipped
- Maximum 3 consecutive scribe-initiated interactions without user input

### Rules of Engagement (RoE)

| Type | Behavior | Max Depth |
|------|----------|-----------|
| **Open** | Advisors respond when @mentioned. Use @all for all. | 1 |
| **Consensus** | All advisors discuss until agreement reached | 5 |
| **Brainstorming** | All advisors iterate on ideas | 2 |

Depth controls how many levels of replies are allowed:
- Depth 1: User message → Advisor response (no back-and-forth between advisors)
- Depth 2: Advisors can reply to each other

### Commands

Slash-command parsing is not part of the runtime path. Conversation actions (for example inviting advisors) are handled by explicit controller endpoints and UI actions.

## Data Model

### New Tables

**conversation_participants** (join table):
- `conversation_id` → conversations
- `advisor_id` → advisors
- `role` (advisor|scribe)
- `position` (ordering)

### Modified Tables

**conversations**:
- `conversation_type` (council_meeting|adhoc)
- `roe_type` (open|consensus|brainstorming)
- `council_id` nullable (only for council_meeting)
- `scribe_initiated_count` (tracks consecutive scribe interactions)
- `title_state` (`user_generated|system_generated|agent_generating|agent_generated`)

**messages**:
- `in_reply_to_id` (self-reference for threading)
- `pending_advisor_ids` (JSON array of advisor IDs awaiting response)

**advisors**:
- `is_scribe` boolean flag (replaces name detection)

## Message Lifecycle

```
User Message Posted
        ↓
`MessagesController#create`
        ↓
`AI.runtime_for_conversation(conversation).user_posted(message)`
        ↓
Runtime creates pending placeholders + writes parent `pending_advisor_ids`
        ↓
Runtime requests first advisor response via `AI.generate_advisor_response(..., async: true)`
        ↓
`AIRunnerJob` executes `AI::Runner` with `RespondTask`
        ↓
`AI::Handlers::ConversationResponseHandler` updates message state/content
        ↓
Runtime `advisor_responded` resolves parent pending list and schedules next advisor
        ↓
[Parent solved?] ──Yes──→ Scribe follow-up for active council meetings only
```

## Conversation compaction

- Compaction is represented as a scribe-authored `Message` with `message_type = compaction`.
- Active compactions use normal message status transitions (`pending` → `responding`) and block new posts/retries via `Conversation#chat_blocked?`.
- Pending/responding compactions render as a temporary `Compacting...` chat item; failed compactions stay visible with an error message.
- Successful compactions store the durable summary in `messages.content` and then disappear from normal chat because `Message.visible_in_chat` hides completed compaction messages.
- `open` mode compacts only after settled turns under pressure; `consensus` and `brainstorming` compact only at scribe round boundaries under the same pressure gate.

## Services

### Runtime classes
Main orchestrators for conversation flow:
- `AI::Runtimes::OpenConversationRuntime`
- `AI::Runtimes::ConsensusConversationRuntime`
- `AI::Runtimes::BrainstormingConversationRuntime`

Shared sequencing behavior (create placeholders, advance pending queue, resolve parent) lives in `AI::Runtimes::ConversationRuntime`.

### Explicit finish flow
- Council meetings are finished by explicit user action (`POST /conversations/:id/finish`)
- `ConversationsController#finish` transitions `active` council meetings directly to `resolved`
- No auto-summary/background summary generation is triggered by finish

### Advisor Invite Flow
`ConversationsController#invite_advisor` handles advisor invitations explicitly:
- Checks advisor exists
- Checks not already in conversation
- Scribe remains auto-present

## Usage

### Creating Council Meeting
```ruby
@council.create_conversation!(
  user: current_user,
  title: "Strategic Planning",
        roe_type: :consensus
)
```

### Creating Adhoc Conversation
```ruby
conversation = account.conversations.create!(
  user: current_user,
  title: "Quick Question",
  conversation_type: :adhoc,
  roe_type: :open
)
conversation.conversation_participants.create!(
  advisor: advisor,
  role: :advisor
)
conversation.ensure_scribe_present!
```

### Adhoc auto-title generation
- Applies only to `adhoc` conversations
- Triggered when content-length and state guards pass
- Skipped when title is user-managed (`title_state = user_generated`)
- Generation failures keep the existing title unchanged

### Inviting advisor
Through explicit endpoint + UI action:
```ruby
conversation.add_advisor(advisor)
```

## Current invariants

- RoE is represented only by `roe_type` values: `open`, `consensus`, `brainstorming`.
- Scribe follow-ups run only for active `council_meeting` conversations.
- Normal `pending` placeholder messages stay hidden until they become `responding`; compaction is the explicit exception and remains visible while `pending` or `responding`.
- Completed compaction messages stay persisted but hidden from normal chat rendering.
- Conversation title automation is state-driven in the `Conversation` model (not a separate title job).

## Runtime ownership

RoE logic and sequencing are implemented in `AI::Runtimes::*ConversationRuntime` classes.
