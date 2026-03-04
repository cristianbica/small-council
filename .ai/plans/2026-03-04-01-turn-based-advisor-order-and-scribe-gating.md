# Plan: Turn-based advisor reply order + stricter scribe gating

Type: bug

## Problem
1. Advisors reply in parallel because all placeholder jobs are enqueued immediately.
2. Scribe can post conclusions before deeper mention-triggered reply chains are resolved.

## Goal
- Ensure advisors reply in order (turn-based) per parent message.
- Prevent scribe follow-up while any pending conversation work exists.

## Changes
1. **Turn-based enqueueing in `ConversationLifecycle`**
   - Create placeholders for all targeted advisors, but enqueue only the first advisor for that parent.
   - After each advisor response/error resolves one advisor, enqueue the next pending advisor placeholder for that same parent.
   - Apply same behavior to mention-triggered advisor fan-out from advisor messages.

2. **Scribe gating hardening**
   - In `advisor_responded`, process mention-triggered fan-out before solved check.
   - In `handle_message_solved`, skip scribe follow-up if conversation has any `pending` messages (global in-conversation guard), ensuring no premature conclusion while chains are active.

3. **Tests**
   - Update lifecycle tests that currently assume all jobs are enqueued immediately.
   - Add tests to verify:
     - only first advisor is enqueued initially,
     - next advisor is enqueued after previous advisor resolves/errors,
     - scribe follow-up is deferred when pending messages exist.

## Out of scope
- UI animation/timing changes
- Queue backend priority tuning

## Verification
- `bin/rails test test/services/conversation_lifecycle_test.rb`
- If needed, related job/lifecycle tests impacted by enqueue semantics
