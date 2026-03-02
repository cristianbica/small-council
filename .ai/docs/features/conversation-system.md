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
| **Consensus** | All advisors discuss until agreement reached | 2 |
| **Brainstorming** | All advisors iterate on ideas | 2 |

Depth controls how many levels of replies are allowed:
- Depth 1: User message → Advisor response (no back-and-forth between advisors)
- Depth 2: Advisors can reply to each other

### Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `/invite` | `/invite @advisor_name` | Add advisor to conversation |

Commands are parsed by `CommandParser` and executed by command classes in `app/services/commands/`.

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
- `title_locked` (manual title override guard; blocks auto-title updates)

**messages**:
- `in_reply_to_id` (self-reference for threading)
- `pending_advisor_ids` (JSON array of advisor IDs awaiting response)

**advisors**:
- `is_scribe` boolean flag (replaces name detection)

## Message Lifecycle

```
User Message Posted
        ↓
[Command?] ──Yes──→ Execute Command
        ↓ No
  Parse Mentions
        ↓
Set pending_advisor_ids
        ↓
Create placeholder messages
        ↓
Enqueue GenerateAdvisorResponseJob
        ↓
Advisor Completes Response
        ↓
Update message status → complete
        ↓
Remove from pending_advisor_ids
        ↓
[Message Solved?] ──Yes──→ Scribe Follow-up? (if < 3 consecutive)
```

## Services

### ConversationLifecycle
Main orchestrator for conversation flow:
- `user_posted_message`: Processes user input, creates pending responses
- `advisor_responded`: Handles completed advisor responses

### Explicit finish flow
- Council meetings are finished by explicit user action (`POST /conversations/:id/finish`)
- `ConversationsController#finish` transitions `active` council meetings directly to `resolved`
- No auto-summary/background summary generation is triggered by finish

### CommandParser
Parses `/` commands from messages. Extensible system for adding new commands.

### Commands::InviteCommand
Validates and executes `/invite @advisor`:
- Checks advisor exists
- Checks not already in conversation
- Cannot invite scribe (auto-present)

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

### Adhoc auto-title after first user message
- Applies only to `adhoc` conversations
- Triggered only for the first user message
- Skipped when `title_locked` is true
- Generation failures keep the existing title unchanged

### Inviting Advisor via Command
User types: `/invite @technical_expert`

Or via UI:
```ruby
conversation.add_advisor(advisor)
```

## Migration Path

Existing data is migrated via `BackfillConversationData`:
1. Sets `conversation_type = 'council_meeting'` for all existing conversations
2. Maps old RoE types: round_robin/on_demand/moderated/silent → open, consensus → consensus
3. Backfills `is_scribe = true` for advisors matching name pattern
4. Creates `conversation_participants` for all council advisors + scribe

## Removed Components

The following old RoE services were deleted:
- `app/services/roe.rb`
- `app/services/roe/base_roe.rb`
- `app/services/roe/factory.rb`
- `app/services/roe/round_robin_roe.rb`
- `app/services/roe/moderated_roe.rb`
- `app/services/roe/on_demand_roe.rb`
- `app/services/roe/silent_roe.rb`
- `app/services/roe/consensus_roe.rb`

The new unified `ConversationLifecycle` handles all RoE logic internally.
