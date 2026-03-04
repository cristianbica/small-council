# Plan: Advisor mention-trigger fan-out + Consensus depth 5 + @user prompt convention

Type: feature/behavior change

## Goal
1. If any advisor message mentions another advisor handle (`@name`), enqueue that advisor to respond.
2. Increase Consensus RoE depth limit from 2 to 5.
3. Prompt convention: advisors should use `@user` only when explicitly requesting a user reply; use plain `user` when referring to the user generally.

## Scope
### A) Mention-trigger from advisor messages
- Update `ConversationLifecycle#advisor_responded` to:
  - Parse mentions from advisor response content
  - Resolve handles to conversation participants
  - Exclude the sender advisor
  - Populate `pending_advisor_ids` on the advisor message
  - Create pending placeholders + enqueue jobs for mentioned advisors
- Keep depth enforcement via existing `create_pending_message_and_enqueue` max-depth checks.

### B) Consensus depth
- Update RoE max depth logic for consensus from `2` to `5` in conversation depth source of truth (likely `Conversation#max_depth`).
- Align user-facing RoE prompt/docs text that currently says consensus depth 2.

### C) Prompt convention for `@user`
- Add explicit rule in shared response policy message (`AI::Client`) about `@user` vs `user` usage.
- Update Scribe default prompt in `Space#create_scribe_advisor` to include the same convention.

## Likely files
- `app/services/conversation_lifecycle.rb`
- `app/models/conversation.rb` (or the current max-depth source)
- `app/models/space.rb`
- `app/libs/ai/client.rb`
- Related tests under `test/services/` and `test/models/` (plus prompt/client tests if needed)

## Verification
- `bin/rails test test/services/conversation_lifecycle_test.rb`
- `bin/rails test test/models/conversation_test.rb`
- `bin/rails test test/ai/unit/client_test.rb`
- Any targeted test files updated/added for mention fan-out behavior
