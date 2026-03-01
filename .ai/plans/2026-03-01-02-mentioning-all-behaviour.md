# Plan: Mentioning @all behaviour

Date: 2026-03-01

## Goal
- Prevent Scribe from responding to @all mentions.
- Ensure advisors respond in a clear, deterministic order for @all.

## Non-goals
- Changing overall mention parsing beyond @all behavior.
- Redesigning conversation orchestration.

## Scope + assumptions
- Scope limited to @all mention handling in conversation flow.
- Assume there is a central dispatcher/orchestrator for advisor responses.

## Steps
1. Identify where @all mentions are detected and routed.
2. Add a guard to exclude Scribe from @all responders.
3. Define and implement advisor response ordering (e.g., council order).
4. Update tests to cover Scribe exclusion and ordering.

## Verification
- Run conversation orchestration tests.
- Reproduce @all in a dev conversation and confirm ordering.

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert @all routing changes and ordering logic.
