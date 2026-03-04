# Plan: Prompt adjustments to reduce unnecessary tooling

Type: bug
Scope: prompt/instruction changes only (no tool registration changes, no hard tool budgets)

## Goal
Reduce cases where advisors search memories/other conversations when the user asks about a previous message in the current conversation.

## Changes
1. Add a dedicated system guidance message in `AI::Client#chat` that enforces:
   - thread-first answering from provided conversation messages,
   - tools only when required information is missing,
   - no cross-conversation/memory lookup for in-thread follow-up unless explicitly requested,
   - no write/admin tool actions without explicit user request.
2. Make guidance context-aware:
   - stronger instruction when current generation is a reply (`context[:message].parent_message` or `context[:parent_message]` present).
3. Keep instructions concise and testable to avoid conflicting prompts.

## Out of scope
- Changing `advisor_tools` tool inventory
- Adding hard runtime tool-call caps
- Refactoring context builder/thread assembly

## Verification
- Add/adjust `AI::Client` unit tests to assert the guidance system message is injected and ordered before user messages.
- Run focused test file for `test/ai/unit/client_test.rb`.
