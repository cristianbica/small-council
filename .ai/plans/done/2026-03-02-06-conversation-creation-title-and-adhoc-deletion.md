# Plan: conversation creation, manual titles, adhoc deletion, and scoped auto-titling

Date: 2026-03-02
Type: feature

## Intake summary (confirmed)
- Change type: feature
- Constraints: DB changes allowed; keep UX minimal (no extra pages/flows)
- Acceptance criteria: exactly the 4 requested behaviors

## Goal
Implement a minimal conversation UX update where council meetings start with topic-only setup (no seeded opening message), conversation titles are user-editable, adhoc conversations can be deleted, and automatic title generation runs only for adhoc conversations after the first user message.

## Non-goals
- No new pages, modals, or alternate creation flows.
- No redesign of message lifecycle or RoE behavior beyond what is required.
- No AI-generated auto-title for council meetings.

## Scope + assumptions
- Existing create flows are in `ConversationsController` (`create_council_meeting`, `create_adhoc_conversation`, `quick_create`).
- Current behavior seeds an initial user message during conversation creation for both types.
- Current UI shows conversation titles but has no explicit title-edit UX in chat header.
- Existing `destroy` action exists; adhoc UX needs explicit, reachable delete affordance and policy alignment.
- Auto-title capability will be introduced via existing AI service layer (`AI::ContentGenerator`) and triggered from first user message path.

## Evidence snapshot
- Seeded first message on create currently happens in both create paths: `app/controllers/conversations_controller.rb`.
- New conversation form currently requires both `title` and `initial_message`: `app/views/conversations/new.html.erb`.
- Chat header currently renders title as static text: `app/views/shared/_chat.html.erb`.
- Adhoc navigation relies on `quick_create` default titles: `app/controllers/conversations_controller.rb`, `app/views/conversations/show.html.erb`.
- Current destroy policy in controller is starter-only; helper/UI checks differ in places: `app/controllers/conversations_controller.rb`, `app/helpers/application_helper.rb`, `app/views/conversations/index.html.erb`.
- No existing conversation auto-title generation method in AI content generator: `app/libs/ai/content_generator.rb`.

## Implementation plan
1. **Data model support for scoped auto-title + manual override guard**
   - Add a conversation-level persisted flag/state to prevent auto-title overwrite after manual edits (e.g., `title_locked` boolean or equivalent explicit state).
   - Backfill existing rows with safe defaults in migration.
   - Keep schema change minimal and isolated to conversation title ownership semantics.

2. **Council meeting creation: topic-only start, no seeded message**
   - Remove `initial_message` requirement from council meeting create flow.
   - Keep `title` as required topic field for council meetings.
   - Stop creating the first user message in `create_council_meeting`; redirect to empty chat where user posts first question/message.
   - Update council-meeting copy in `new` view to reflect topic-only start.

3. **Adhoc creation alignment and first-message entry point**
   - Remove seeded initial message creation from adhoc create/quick-create paths so first actual user chat message is the first message.
   - Keep adhoc creation minimal (existing flow), with no additional screens.
   - Preserve advisor participant validation and scribe inclusion behavior.

4. **Manual title editing for all conversation types**
   - Add an inline, minimal title edit control in shared chat header (`shared/_chat`) for all conversations.
   - Wire to existing `PATCH /conversations/:id` update path with explicit title update handling.
   - On successful manual title update, mark title as user-managed (lock auto-title for that conversation).
   - Keep RoE update behavior intact and avoid introducing separate edit screens.

5. **Adhoc-only auto-title generation after first user message**
   - Introduce `AI::ContentGenerator` method/template for concise conversation title generation from first user message content.
   - Trigger auto-title asynchronously after message create, but only when all are true:
     - conversation is `adhoc`
     - this is the first user message in that conversation
     - title is not manually locked
   - Apply conservative fallback: if generation fails/empty, keep current title unchanged.

6. **Delete behavior: explicitly supported for adhoc conversations**
   - Ensure adhoc conversation UI has visible delete action in primary adhoc experience (`conversations/show` sidebar/header) and list view as applicable.
   - Align authorization/policy checks between helper and controller to avoid contradictory behavior.
   - Keep UX minimal with existing confirmation pattern and current redirect behavior.

7. **Tests and regressions (targeted)**
   - Update controller tests to reflect no seeded message on create for council and adhoc flows.
   - Add/adjust message/controller/job tests for first-message adhoc auto-title trigger and guards (non-adhoc, second message, manual lock).
   - Add/adjust view/controller tests for title edit submission and persistence.
   - Add/adjust destroy tests for adhoc delete affordance + authorization consistency.

## Acceptance checklist (mapped to request)
- [ ] **(1) Council meetings**: meeting creation no longer seeds an initial message; form asks only for topic/title; conversation begins empty so users ask in chat afterward.
- [ ] **(2) All conversations**: title can be changed manually via minimal in-context UI and persists.
- [ ] **(3) Adhoc conversations**: adhoc conversations can be deleted through reachable UI, with consistent authorization.
- [ ] **(4) Auto-title generation**: automatic title generation runs only for adhoc conversations and only after first user message; never for council meetings and never after manual title lock.

## Verification plan
- `bin/rails test test/controllers/conversations_controller_test.rb`
- `bin/rails test test/controllers/conversations_controller_comprehensive_test.rb`
- `bin/rails test test/controllers/messages_controller_test.rb`
- `bin/rails test test/models/conversation_test.rb`
- Additional focused test file(s) added for auto-title service/job path (if introduced)

## Risks / edge cases
- **Race condition on first message**: concurrent posts could attempt double auto-title; mitigate with persisted guard + idempotent check before update.
- **Manual edit vs async auto-title**: user edits title while auto-title job is running; manual lock must win.
- **Authorization drift**: helper and controller currently differ; unify source-of-truth to avoid exposed-but-denied actions.
- **Legacy test assumptions**: many tests expect `initial_message` behavior; update only conversation-related tests necessary for new contract.
- **LLM availability**: auto-title generation may fail when no model is configured; fallback must keep conversation usable with existing title.

## Doc impact
- doc impact: updated
- Update expected in:
  - `.ai/docs/features/conversations.md` (creation flow, title edit capability, adhoc delete behavior)
  - `.ai/docs/features/conversation-system.md` (message lifecycle note for adhoc first-message auto-title)

## Memory impact
- memory impact: none (feature-specific behavior; not a durable repo-wide convention)

## Approval gate
- Approve this plan?
