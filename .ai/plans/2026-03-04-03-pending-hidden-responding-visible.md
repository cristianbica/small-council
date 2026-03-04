# Plan: Pending hidden, responding visible

Type: bug

## Goal
- `pending` placeholders are internal and not shown in UI.
- When job actually starts, message status becomes `responding` and the placeholder appears.

## Changes
1. Add `responding` status to `Message` enum.
2. `ConversationLifecycle#create_pending_message`: create status `pending` and do not broadcast.
3. `GenerateAdvisorResponseJob#perform`: accept `pending/responding`; on `pending`, transition to `responding` and broadcast append.
4. Hide `pending` from initial UI loads:
   - `ConversationsController#show` message query excludes `pending`
   - `MessagesController#create` error render query excludes `pending`
   - `_message_thread` excludes `pending` replies when recursively rendering.
5. Update tests for enum values and new responding behavior.

## Verification
- `bin/rails test test/services/conversation_lifecycle_test.rb`
- `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
- `bin/rails test test/models/message_test.rb`
