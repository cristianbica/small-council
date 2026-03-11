# Plan: Fix Scribe Mention Sequencing in Consensus/Brainstorming

Date: 2026-03-11

## Problem
In `consensus` and `brainstorming`, when the scribe posts a root message that mentions advisors, no advisor responses are scheduled. Conversation stalls.

## Root Cause
`ConversationRuntime#advisor_responded` returns early unless `message.reply?`.
Scribe moderator messages are root messages, so they bypass sequencing logic entirely.

## Scope
- Runtime sequencing for `consensus` and `brainstorming` only.
- Tests for the regression.

## Proposed Changes
1. Override `advisor_responded` in:
   - `AI::Runtimes::ConsensusConversationRuntime`
   - `AI::Runtimes::BrainstormingConversationRuntime`
2. In the override:
   - compute `advisors = advisors_to_respond(message)`
   - if any, call `schedule_advisors_responses(advisors, message)` and return
   - otherwise fall back to `super` for existing reply-chain behavior
3. Add tests proving a root scribe message with mentions schedules advisors in both runtimes.

## Files
- `app/libs/ai/runtimes/consensus_conversation_runtime.rb`
- `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb`
- `test/libs/ai/runtimes/consensus_conversation_runtime_test.rb`
- `test/libs/ai/runtimes/brainstorming_conversation_runtime_test.rb`

## Verification
- Run targeted runtime tests:
  - `test/libs/ai/runtimes/consensus_conversation_runtime_test.rb`
  - `test/libs/ai/runtimes/brainstorming_conversation_runtime_test.rb`

## Out of Scope
- Mention parsing normalization (spaces/case/aliases).
- Open runtime behavior changes.
