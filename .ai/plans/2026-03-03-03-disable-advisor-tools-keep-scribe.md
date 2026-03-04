# Plan: Disable tools for non-scribe advisors

Type: bug
Scope: tool wiring only

## Goal
Prevent non-scribe advisors from invoking any tools. Keep Scribe tool access unchanged.

## Proposed changes
1. Update `AI::ContentGenerator#advisor_tools` so:
   - non-scribe advisors receive `[]`
   - scribe keeps existing read/admin/write tool set
2. Update unit tests that currently expect non-scribe tool availability:
   - `test/ai/unit/content_generator_test.rb`
   - keep scribe tool expectations intact
3. Update docs that currently state all advisors have read-only tools:
   - `.ai/docs/features/ai-integration.md`
   - `.ai/docs/features/advisors.md` (if present wording conflicts)

## Out of scope
- Runtime tool budget/limits
- Prompt policy changes
- Any tool behavior changes for Scribe

## Verification
- Run focused tests:
  - `bin/rails test test/ai/unit/content_generator_test.rb`
  - optionally `bin/rails test test/ai/unit/client_test.rb` if needed for wiring side effects
