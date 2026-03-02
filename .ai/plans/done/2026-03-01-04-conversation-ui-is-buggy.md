# Plan: Conversation UI is buggy

Date: 2026-03-01

## Goal
- Eliminate extra scrollbars, fix avatar centering, and align chat bubbles with DaisyUI chat-* classes.

## Non-goals
- Redesigning the entire conversation UI layout or branding.
- Changing message data structures.

## Scope + assumptions
- Scope limited to conversation view templates and CSS classes.
- Assume DaisyUI chat-* classes are available in the current Tailwind build.

## Steps
1. Audit conversation view markup for nested overflow/scroll containers.
2. Update avatar markup to center initials properly.
3. Replace custom bubble markup with DaisyUI chat-* classes.
4. Adjust layout classes to ensure a single scroll container.
5. Update any UI tests or snapshots if present.

## Verification
- Manual UI check in dev for scrollbars and avatar alignment.
- Confirm chat bubbles render with DaisyUI styles.

## Doc impact
- doc impact: none

## Rollback (if applicable)
- Revert view template and CSS class changes.
