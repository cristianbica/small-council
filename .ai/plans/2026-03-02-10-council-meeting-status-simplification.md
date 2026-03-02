# Plan: Council meeting status simplification (remove concluding + auto-summary)

Date: 2026-03-02
Workflow: change (`refactor/bugfix` hybrid)

## Goal
Remove the `concluding` state and all end-of-conversation summary tooling/automation. Meetings should only end via explicit user action (Finish button). No built-in summary tool should remain in this flow.

## Non-goals
- No redesign of memory model/types.
- No broad chat UX redesign beyond status/finish controls needed for this behavior.
- No changes to non-conversation AI tooling unrelated to finishing/summaries.

## Scope + assumptions
- In scope: conversation statuses, conclusion lifecycle path, finish tool path, summary job path, affected UI status alerts, and impacted tests/docs.
- Assumption A: “Finish button” transitions meeting directly to `resolved` (not `archived`).
- Assumption B: existing `archive` remains separate and unchanged.
- Assumption C (updated): `summarize_conversation` tool is removed as part of this change; if users need summaries, they can still request Scribe behavior via normal chat/tooling without the dedicated summarize tool.

## 1) Current behavior inventory (evidence-backed)

### A. Automatic conclusion + summary trigger path
- `app/services/conversation_lifecycle.rb`
  - `begin_conclusion_process` sets `status: :concluding` and enqueues `GenerateConversationSummaryJob`.
- `app/libs/ai/tools/conversations/finish_conversation_tool.rb`
  - Calls `ConversationLifecycle#begin_conclusion_process` and returns `status: "concluding"`.
- `app/jobs/generate_conversation_summary_job.rb`
  - Runs only when conversation is `concluding?`, generates summary, writes `draft_memory`, creates memory, broadcasts summary-ready Turbo update.

### B. Status model + UI currently encode concluding
- `app/models/conversation.rb` includes status enum values: `active`, `concluding`, `resolved`, `archived`.
- `app/helpers/application_helper.rb` maps `concluding` -> warning badge.
- `app/views/shared/_chat.html.erb` shows “Generating summary... Please wait.” on `concluding`, and “Conversation resolved. Memory saved.” on `resolved`.
- `app/views/conversations/index.html.erb` has explicit `concluding` badge branch.

### C. Tooling exposure
- `app/libs/ai/content_generator.rb` exposes `AI::Tools::Conversations::FinishConversationTool` for Scribe.
- Current architecture docs also advertise finish tool / summary job path.

### D. Test surface asserting old behavior
- Lifecycle: `test/services/conversation_lifecycle_test.rb`, `test/services/conversation_lifecycle_comprehensive_test.rb`.
- Job: `test/jobs/generate_conversation_summary_job_test.rb`, `test/jobs/generate_conversation_summary_job_comprehensive_test.rb`.
- Tool: `test/ai/unit/tools/conversations/finish_conversation_tool_test.rb`.
- Tool wiring: `test/ai/unit/content_generator_test.rb` expects finish tool for scribe.
- Model/helper/controller tests reference `concluding`: 
  - `test/models/conversation_test.rb`
  - `test/models/conversation_comprehensive_test.rb`
  - `test/helpers/application_helper_test.rb`
  - `test/controllers/conversations_controller_comprehensive_test.rb`

## 2) Exact code removal/refactor steps

1. Remove automatic summary orchestration
   - Delete `ConversationLifecycle#begin_conclusion_process` from `app/services/conversation_lifecycle.rb`.
   - Remove any remaining callers/references.

2. Remove finish tool automatic path
   - Delete `app/libs/ai/tools/conversations/finish_conversation_tool.rb`.
   - Remove its registration from `app/libs/ai/content_generator.rb`.
   - Update any tool-count assumptions in tests/docs.

3. Remove summary background job path
   - Delete `app/jobs/generate_conversation_summary_job.rb`.
   - Remove any references in code/tests/docs.

4. Remove summarize tool path
   - Delete `app/libs/ai/tools/conversations/summarize_conversation_tool.rb`.
   - Remove its registration from `app/libs/ai/content_generator.rb`.
   - Remove references in docs/tests and adjust tool-count assertions.

5. Simplify status model (drop `concluding`)
   - Update `app/models/conversation.rb` enum to `active`, `resolved`, `archived`.
   - Add a data migration to remap existing `concluding` records to final status (see section 3).

6. Add explicit user finish action (UI-driven, no auto-summary)
   - Add conversation member route (e.g., `POST /conversations/:id/finish`) in `config/routes.rb`.
   - Add `finish` action in `app/controllers/conversations_controller.rb`:
     - authorization aligned with existing manage/delete rules,
     - allowed only from `active`,
     - update status directly to `resolved`,
     - no job enqueue, no summary generation.
   - Add explicit Finish control in meeting/chat UI (likely `app/views/shared/_chat.html.erb`; optionally list views if required by current UX patterns).

7. Remove concluding-specific UI branches
   - `app/helpers/application_helper.rb`: remove `concluding` branch.
   - `app/views/shared/_chat.html.erb`: remove concluding alert and resolved text claiming auto-memory side effect.
   - `app/views/conversations/index.html.erb`: remove concluding badge logic.

8. Ensure no automatic/manual summary tool remains in this finish flow
   - Ensure no automatic memory creation remains tied to finish/conclusion code path.
   - Ensure no `summarize_conversation` tool remains registered/available.

## 3) Backward compatibility / data considerations

1. Existing DB records with `status = 'concluding'`
   - Add migration to remap to `resolved` (preferred) or `active` (if product chooses).
   - Recommendation: `concluding -> resolved` to preserve user intent that meeting was being finished.

2. Enum safety
   - Ensure app code no longer calls `concluding?`/`concluding!` before enum change is deployed.
   - Deploy order should include migration and code in one release to avoid transient errors.

3. Historical fields
   - `draft_memory` column can remain for now (out of scope unless explicitly requested); removing auto-summary job just stops populating it automatically.

4. Invariants after change
   - Meeting completion is user-explicit (`finish` endpoint/button), not tool-initiated.
   - No automatic summary job enqueue on status transition.

## 4) Test updates/additions scope

1. Remove/delete obsolete tests
   - Delete job test files:
     - `test/jobs/generate_conversation_summary_job_test.rb`
     - `test/jobs/generate_conversation_summary_job_comprehensive_test.rb`
    - Delete finish tool test:
     - `test/ai/unit/tools/conversations/finish_conversation_tool_test.rb`
    - Delete summarize tool test:
       - `test/ai/unit/tools/conversations/summarize_conversation_tool_test.rb`
   - Remove lifecycle tests asserting `begin_conclusion_process` behavior.

2. Update existing tests for status changes
   - `test/models/conversation_test.rb` expected statuses.
   - `test/models/conversation_comprehensive_test.rb` remove/replace concluding predicate and transition assertions.
   - `test/helpers/application_helper_test.rb` remove concluding badge case.
   - `test/controllers/conversations_controller_comprehensive_test.rb` adjust non-active invite scenario to use `resolved` or `archived`.

3. Update tool wiring tests
   - `test/ai/unit/content_generator_test.rb`:
     - remove expectations for `FinishConversationTool`,
   - remove expectations for `SummarizeConversationTool`,
   - update scribe tool count.

4. Add finish endpoint coverage
   - Controller tests for `ConversationsController#finish`:
     - success path (active -> resolved),
     - rejects non-active statuses,
     - authorization checks,
     - no summary job enqueue.

## 5) Verification checklist (run after implementation)

Focused checks first:
- `bin/rails test test/services/conversation_lifecycle_test.rb`
- `bin/rails test test/services/conversation_lifecycle_comprehensive_test.rb`
- `bin/rails test test/models/conversation_test.rb`
- `bin/rails test test/models/conversation_comprehensive_test.rb`
- `bin/rails test test/helpers/application_helper_test.rb`
- `bin/rails test test/controllers/conversations_controller_comprehensive_test.rb`
- `bin/rails test test/ai/unit/content_generator_test.rb`


Then broader safety check:
- `bin/rails test`

Manual sanity checks:
- Open active council meeting, click Finish, confirm status becomes `resolved` immediately.
- Confirm no “generating summary” state/alerts appear.
- Ask Scribe for a summary manually; confirm summary can still be produced and memory can be created via normal tool flow.

## 6) Doc impact + memory impact expectations

- doc impact: updated
  - Update docs describing status model and finish behavior:
    - `.ai/docs/features/conversation-system.md`
    - `.ai/docs/features/conversations.md`
    - `.ai/docs/features/data-model.md`
    - `.ai/docs/features/ai-integration.md`
    - `.ai/docs/patterns/tool-system.md`
    - `.ai/docs/overview.md` (job list)
  - If finish UI endpoint is introduced, document route/action.

- memory impact: expected
  - Add one bullet to `.ai/MEMORY.md` after implementation verification, e.g.:
    - “Conversation statuses are `active/resolved/archived`; `concluding` and automatic summary generation were removed; meeting completion is explicit user finish action.”

## Risks / watchouts
- Potential hidden references to `concluding` in less-traveled tests/docs.
- Tool-count assertions may fail broadly after finish tool removal.
- If users relied on auto-generated `conversation_summary` memories, behavior changes to fully manual summary requests.

## Approval gate
Approve this plan?