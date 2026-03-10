# Plan 03: Documentation Update Plan

- Date: `2026-03-10`
- Derived from:
- `.ai/plans/2026-03-10-01-staged-file-test-matrix.md`
- `.ai/plans/2026-03-10-02-replacement-cleanup-plan.md`
- Goal: update `.ai/docs` to reflect final refactor state after cleanup, without doing a minimal patch-only pass or a full rewrite.
- Non-goals: rewriting all docs, changing product code, updating docs before cleanup outcomes are validated.

## Update Strategy

1. Lock final technical state after Plan 02 cleanup validation.
2. Apply focused doc updates in overview + impacted feature/pattern docs.
3. Record durable conventions/commands in memory docs.
4. Run doc consistency checks (cross-links, naming, and canonical path usage).

## Code-to-Docs Mapping

| Change Area | Evidence from Refactor | Docs to Update | Update Scope |
| --- | --- | --- | --- |
| New form filler flow (`app/controllers/form_fillers_controller.rb`, new views/js/tests) | New endpoint, modal flow, Turbo rendering, fixtures/tests | `.ai/docs/overview.md`, `.ai/docs/features/form-fillers.md`, `.ai/docs/features/conversations.md` | Clarify where form fillers sit in user flow, runtime calls, and UI behavior. |
| Conversation UI restructure (chat/message partial relocation, composer/sidebar additions, message interactions rewrite) | New conversation partials and removal of legacy message partial set | `.ai/docs/features/conversations.md`, `.ai/docs/patterns/ui-components.md`, `.ai/docs/patterns/turbo-streams.md` | Document new component boundaries and Turbo frame/layout conventions. |
| AI runtime decomposition (`app/libs/ai/**` large additions) | New agents/contexts/handlers/runtimes/tasks/tools/schemas/trackers | `.ai/docs/features/ai-integration.md`, `.ai/docs/patterns/tool-system.md`, `.ai/docs/patterns/architecture.md`, `.ai/docs/patterns/background-jobs.md` | Describe runtime layers, responsibilities, entrypoints, and test strategy. |
| Memories/advisors tool expansion | New memory and advisor tool classes + tests | `.ai/docs/features/memory-management.md`, `.ai/docs/features/advisors.md`, `.ai/docs/features/model-interactions.md` | Update tool catalog, expected outputs, and integration touchpoints. |
| Layout and routing changes | `config/routes.rb`, new layout partials, modal frame template | `.ai/docs/overview.md`, `.ai/docs/features/ui-framework.md`, `.ai/docs/features/conversation-system.md` | Update route ownership and rendering shell conventions. |
| Database change (`tool_calls` on messages) | New migration + schema update + message model changes | `.ai/docs/features/data-model.md`, `.ai/docs/features/model-interactions.md` | Document message schema evolution and tool-call persistence semantics. |
| Test topology expansion | New `test/libs/ai/**`, fixtures, runtime tests, controller tests | `.ai/docs/patterns/testing.md`, `.ai/docs/features/README.md` | Reflect test suite organization and expected coverage gates for staged refactors. |

## Required Memory Updates

| Memory File | Required Entry |
| --- | --- |
| `.ai/MEMORY.md` | Add one short durable bullet for the new AI runtime/test command conventions discovered during this refactor. |

## Acceptance Checklist

- [ ] `overview.md` reflects current architecture entrypoints and primary runtime boundaries.
- [ ] Feature docs match final controller/view/routes reality after cleanup (no references to deleted legacy partials/layouts).
- [ ] Pattern docs capture new AI runtime layering and tool-system conventions.
- [ ] Testing docs include staged-refactor execution order and changed-line coverage target (`100%` changed/new lines).
- [ ] Docs reference current file paths only; no stale renamed/deleted paths remain.
- [ ] `.ai/MEMORY.md` includes durable repo fact(s) discovered from this refactor.
- [ ] Cross-links in `.ai/docs/features/README.md` and pattern indexes resolve.
- [ ] Doc updates are scoped and targeted (not a full rewrite, not a minimal one-line pass).

## Planned Verification Commands

- `grep -R "shared/_chat\|layouts/conversation\|messages/_interactions_" .ai/docs`
- `grep -R "form_filler\|AI::Runner\|tool_calls" .ai/docs`
- `grep -R "app/views/messages/_message.html.erb" .ai/docs`
- Manual link/path pass across updated `.ai/docs` files.

## Exit Criteria

- Documentation accurately describes final post-cleanup implementation.
- No stale references to replaced/deleted artifacts remain in `.ai/docs`.
- Memory update is recorded in `.ai/MEMORY.md`.

## Doc Impact

- `doc impact`: updated (planned in this plan; execute after cleanup validation).
