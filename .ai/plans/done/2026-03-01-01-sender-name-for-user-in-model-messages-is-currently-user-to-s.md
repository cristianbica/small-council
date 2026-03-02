# Plan: Sender name for User in model messages is currently `user.to_s`

Date: 2026-03-01

## Goal
- Introduce a `display_name` contract for sender classes and use it when serializing model messages.
- For advisors, `display_name` returns the advisor name.
- For users, `display_name` returns the literal string "user".

## Non-goals
- Redesigning the full message formatting pipeline.
- Adding user-provided display names or profile settings.

## Scope + assumptions
- Scope limited to sender naming when serializing messages to LLM context.
- Sender classes (at least `User` and `Advisor`) can define a `display_name` method.
- Serialization uses `sender.display_name` when available.

## Steps
1. Locate message serialization code that builds `sender_name` for LLM context.
2. Add `display_name` to `Advisor` (returns `name`) and `User` (returns "user").
3. Update serialization logic to use `sender.display_name` (with safe fallback if missing).
4. Update/extend tests to cover both User and Advisor sender names in payloads.
5. Validate LLM context payloads contain the new sender name values.

## Verification
- Run relevant model/message serialization tests.
- Manually inspect a sample LLM payload to confirm sender name.

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert the sender name logic to the prior `user.to_s` behavior.
