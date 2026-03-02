# Plan: Space scoping for conversations and related resources

Date: 2026-03-01

## Goal
- Ensure conversations are scoped to `Current.space` by adding `space_id` to `conversations` and using it in queries.

## Non-goals
- Redesigning the multi-tenant (account) scoping model.
- Changing business logic unrelated to space scoping (UI tweaks, new features).
- Changing how councils/advisors/memories are scoped (beyond enforcing via conversation space).

## Scope + assumptions
- Add `space_id` to `conversations` (non-null), backfilled from `conversation.council.space` for existing rows.
- Scope: conversation lifecycle endpoints, message creation, participant/advisor links, summaries, and any tooling that references conversation data.
- Scope: background jobs and service objects that load conversations/messages.
- Scope: authorization/policies that guard conversation access.
- Assumption: `Current.space` is set per request and conversations must be associated to a space.

## Steps
1. **Migration:** Add `space_id` to `conversations` (non-null) with index; backfill from `conversations.council.space`.
2. **Model:** Add `belongs_to :space` to Conversation and validate presence.
3. **Queries:** Update conversation lookups to use `Current.space.conversations` (or equivalent) everywhere.
4. **Services/tools/jobs:** Ensure any conversation/message lookups enforce space scope.
5. **Tests:** Add/adjust tests to cover cross-space access attempts for conversation show, message create, invite advisor, and job/service lookup paths.

## Verification
- Run relevant controller/service/job tests covering conversation access across spaces.
- Add/confirm integration test: attempting to access a conversation from a different space is rejected (404/403 as expected).
- Manual check (if needed): log in as two users in different spaces; ensure conversation list and direct URL access are space-scoped.

## Doc impact
- Update: `.ai/docs/features/conversations.md` (add explicit space scoping behavior and access constraints).

## Rollback (if applicable)
- Revert migration and space-scoped query changes; remove new test expectations if they conflict.
