# Plan: Pending/Responding visibility and enqueue timing

Type: bug

## Goal
- Keep advisor placeholders hidden until work starts.
- Show placeholder only when advisor job is started (responding).

## Changes
1. Add message status `responding`.
2. Create placeholders as `pending` (not shown in UI).
3. In `enqueue_next_pending_for`, atomically pick next `pending`, mark `responding`, broadcast append, enqueue job.
4. Update UI query/render to exclude `pending` messages from initial conversation load.
5. Keep completion/error as replace broadcasts.
6. Add/update tests for status behavior and sequential enqueue visibility.

## Verification
- `bin/rails test test/services/conversation_lifecycle_test.rb`
- `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
- `bin/rails test test/models/message_test.rb`
