# Plan: Use a a diff gem instead of our own diff implementation

Date: 2026-03-01

## Goal
- Replace custom diff implementation with a vetted gem (e.g., diffy).

## Non-goals
- Redesigning diff output formatting beyond compatibility needs.
- Changing unrelated text comparison features.

## Scope + assumptions
- Scope limited to the existing diff utility usage in the app.
- Assume gem addition is acceptable and compatible with current Ruby version.

## Steps
1. Locate current diff implementation and usage points.
2. Evaluate diffy API for required output and edge cases.
3. Replace implementation with gem usage and adjust formatting.
4. Update tests for diff output expectations.

## Verification
- Run unit tests covering diff behavior.
- Manually compare old vs new diff output for key cases.

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert to custom diff implementation and remove gem usage.
