# Plan: Retry advisor response on API error

Type: bug

## Intake
1. Change summary: add a retry action when an advisor response fails with API/provider error.
2. Outcome criteria: user can click a visible Retry button on errored advisor messages and the same message is reprocessed.
3. Constraints: minimal scope, no schema changes, preserve existing turn-based flow and message threading.

## Goal
- For advisor messages in `error` status, expose a UI action to retry generation.
- Retry should transition message back into processing and re-run `GenerateAdvisorResponseJob` for that same message.

## Changes
1. Add member route for retry on messages under conversations.
2. Add `MessagesController#retry` with guards:
   - message must be advisor-sent and currently `error`
   - reset status to `pending` (and clear error content) before enqueue
   - enqueue `GenerateAdvisorResponseJob` for the message/advisor/conversation ids
   - respond with redirect + turbo stream compatibility via existing broadcasts.
3. Update message partial to show `Retry` button only for advisor `error` messages.
4. Add focused controller/view tests for visibility and retry behavior.

## Verification
- `bin/rails test test/controllers/messages_controller_test.rb`
- `bin/rails test test/views/messages/message_partial_test.rb`
- `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
