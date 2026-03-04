# Plan: Include conversation id in advisor conversation prompt context

Type: feature

## Intake
1. Change summary: include the current conversation id in the prompt context sent to advisors in conversation chat.
2. Outcome criteria: the system context message includes conversation id when available.
3. Constraints: minimal patch; no schema/API changes.

## Goal
- Ensure advisor prompts have explicit conversation identifier to improve traceability and grounding.

## Changes
1. Update `AI::Client#build_council_context_message` to append `Conversation ID: <id>` when `context[:conversation]` has an id.
2. Extend existing unit test in `test/ai/unit/client_test.rb` that validates ordered context messages to assert conversation id appears.

## Verification
- `bin/rails test test/ai/unit/client_test.rb`
