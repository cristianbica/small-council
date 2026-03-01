# Plan: Advisors' models receives also "is thinking ..." messages

Date: 2026-03-01

## Goal
- Stop sending non-essential "is thinking..." messages to advisor model context.

## Non-goals
- Changing UI typing indicators or client-side status updates.
- Redesigning the entire message pipeline.

## Scope + assumptions
- Scope limited to server-side messages passed to LLM providers.
- Assume "is thinking..." is an internal/system status message.

## Steps
1. Locate where "is thinking..." messages are generated and queued.
2. Add a filter to exclude them from LLM context payloads.
3. Update tests to ensure status messages are not included.

## Verification
- Run LLM context/message serialization tests.
- Inspect a sample provider request payload for absence of status messages.

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert filtering so status messages are included again.
