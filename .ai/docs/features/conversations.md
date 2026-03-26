# Conversations

Users run advisor conversations inside the active `Current.space`.

## Overview

A conversation belongs to one space and one user, and is either:
- `council_meeting` (tied to a council)
- `adhoc` (direct advisor thread)

Messages are persisted first, then runtime orchestration schedules advisor replies asynchronously via `AI::Runner` and `AIRunnerJob`.

## User flows

### Start a conversation
1. Open councils or the adhoc conversation entrypoint.
2. Create a conversation with title and RoE (`open`, `consensus`, `brainstorming`).
3. Post the first user message.

### Post a message
1. `MessagesController#create` saves the user message.
2. Controller calls `AI.runtime_for_conversation(@conversation).user_posted(@message)`.
3. Runtime creates hidden `pending` placeholders for selected advisors.
4. Async runs transition placeholders to `responding`, then `complete` or `error`.

### Configure participant model and tools
1. In conversation header, click an advisor participant chip.
2. A modal opens with participant-scoped settings.
3. Choose an optional participant model override (`llm_model_id`) or inherit advisor defaults.
4. Choose tools mode:
	- inherit defaults (`tools = nil`)
	- custom allowed tools (`tools = []` means explicit no-tools)
5. Save updates to `ConversationParticipant`, and chips refresh via Turbo Streams.

### Finish or archive
- `POST /conversations/:id/finish` transitions active council meetings to `resolved`.
- `POST /conversations/:id/archive` transitions to `archived`.

## Rules of Engagement (RoE)

| Mode | Behavior | Max depth |
|------|----------|-----------|
| `open` | Mentioned advisors respond (`@all` for broad invite) | 1 |
| `consensus` | Group discussion until consensus | 5 |
| `brainstorming` | Short collaborative idea iteration | 2 |

RoE behavior is implemented in `AI::Runtimes::*ConversationRuntime`.

## Auto-title behavior (adhoc)

Adhoc titles are generated from conversation content once enough message content exists:
- Triggered from `Conversation` update callbacks.
- Guarded by `title_state` transitions: `system_generated -> agent_generating -> agent_generated`.
- Uses `AI.run` with prompt `conversations/title_generator` and tool `conversations/update_conversation`.
- Manual title edits set `title_state` to `user_generated` and prevent auto-title overwrite.

See [Conversation Title Lifecycle](conversation-title-lifecycle.md).

## Technical

### Key routes
- `/conversations/:id` (`show`, `update`, `destroy`)
- `/conversations/:id/finish` (`POST`)
- `/conversations/:id/archive` (`POST`)
- `/conversations/:id/invite_advisor` (`POST`)
- `/conversations/:conversation_id/participants/:id/edit` (`GET`)
- `/conversations/:conversation_id/participants/:id` (`PATCH`)
- `/conversations/:conversation_id/messages` (`POST`)
- `/conversations/:conversation_id/messages/:id/retry` (`POST`)

### Key models
- `Conversation`: status, `roe_type`, `conversation_type`, `title_state`, `space_id`, optional `council_id`
- `Message`: polymorphic sender, response status, pending advisor tracking
- `ConversationParticipant`: advisor or scribe role and ordering, plus optional participant-scoped `llm_model_id` and `tools`

### Key classes
- `app/controllers/conversations_controller.rb`
- `app/controllers/messages_controller.rb`
- `app/models/conversation.rb`
- `app/libs/ai/runtimes/conversation_runtime.rb`
- `app/libs/ai/handlers/conversation_response_handler.rb`

## Access and boundaries

- Access is tenant-scoped (`acts_as_tenant`) and space-scoped (`Current.space`).
- Conversation operations outside the active space are blocked.
- Deletion is restricted to conversation owner or council creator (`Conversation#deletable_by?`).
