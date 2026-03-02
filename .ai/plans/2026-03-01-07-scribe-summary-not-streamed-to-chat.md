# Plan: Scribe summary not streamed to chat

Date: 2026-03-01

## Goal
- Ensure Scribe’s automatic summary is streamed to chat in real time without refresh.

## Non-goals
- Changing summary content or timing logic.
- Reworking the entire Turbo Streams setup.

## Scope + assumptions
- Scope limited to summary generation job and Turbo Stream broadcast.
- Assume summaries are created in a background job.

## Steps
1. Locate summary generation and broadcast logic.
2. Identify why the broadcast is missing or not targeting the chat stream.
3. Add or fix Turbo Stream broadcast for summary messages.
4. Update tests to ensure streaming behavior.

## Verification
- Run relevant job/integration tests.
- Manually end a conversation and confirm summary appears live.

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert broadcast changes to previous behavior.
