# Plan: Minimal chat UI patterns for DaisyUI chat component

Date: 2026-03-01

## Goal
- Implement a minimal chat layout compatible with DaisyUI chat, preserving copy button, model interaction modal, timestamps, and avatars, grounded in the research.

## Non-goals
- Full redesign of navigation or composer workflow.
- Introducing new dependencies or JS frameworks.

## Scope + assumptions
- Use DaisyUI chat component docs as the primary structural reference.
- Apply neutral, minimal styling (no new theme).
- Keep all existing conversation actions and metadata.

## Steps
1. Update conversation message partials to the exact DaisyUI chat structure (chat/chat-image/chat-header/chat-bubble/chat-footer).
2. Apply placement: user = chat-end, advisors = chat-start, with neutral minimal bubble colors.
3. Preserve existing metadata/actions (timestamps, copy button, model interaction modal).
4. Ensure single scroll region (remove nested scroll containers if present).
5. Adjust spacing/width constraints to keep bubbles minimal and readable.
6. Manually verify layout across common message types (user/advisor, long/short, errors).

## Verification
- Manual UI review on conversation page:
  - single scroll region
  - avatars aligned
  - visible bubbles
  - actions and timestamps present

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert view partial and layout changes.
