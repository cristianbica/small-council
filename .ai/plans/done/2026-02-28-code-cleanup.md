# Plan: Code Cleanup — Dead Code, Simplifications, and Clarity Fixes

Date: 2026-02-28

## Goal
- Remove dead/unused code, eliminate redundant logic, and improve naming/comment clarity across the Rails app with zero behavior change.

## Non-goals
- No public API, route, or database schema changes.
- No behavior changes whatsoever.
- No test additions beyond deleting tests that exclusively cover deleted code.
- No changes to the UI layer or views.

## Scope + assumptions
- All items are HIGH confidence unless marked `[SKIP if unsure]`.
- "Never used in app/" means: no call site found in `app/`, `lib/`, `config/`, or `bin/`; only found in `test/` or `spec/`.
- Scopes defined on models but never queried in app code are dead code.
- Items grouped by file for minimal diff blast radius.
- Each task is estimated ≤ 30 min.

---

## Steps

### Section 1 — Dead Code to Delete

**Task 1.1 — `app/libs/ai/content_generator.rb`** (~10 min)
- Delete `build_conversation_messages` (lines 359–367). Only `build_conversation_messages_with_thread` is used.
- Delete `TEMPLATES[:advisor_response_with_mentions]` entry (lines 136–168). `render_template(:advisor_response_with_mentions, ...)` is never called.

**Task 1.2 — `app/libs/ai/context_builders/base_context_builder.rb`** (~5 min)
- Delete `council` helper method (lines 76–78). No subclass calls it.
- Delete `validate_space!` method (lines 126–134). Subclasses have their own `validate_space_context!`.

**Task 1.3 — `app/libs/ai/context_builders/scribe_context_builder.rb`** (~5 min)
- Delete entire file. Never referenced in any app/ code.
- Delete corresponding test file (only coverage for this dead class).

**Task 1.4 — `app/libs/ai/tools/base_tool.rb`** (~10 min)
- Delete `format_result` method (lines 78–81). Never called anywhere.
- Delete `context_fetch` and `context_require` methods (lines 99–110). All tools use `context[:key]` directly.

**Task 1.5 — `app/services/command_parser.rb`** (~5 min)
- Delete `CommandParser.available_commands` class method (lines 30–32). Only called in its own test.
- Delete `CommandParser.command?` class method (lines 24–27). App uses `message.command?` or `CommandParser.parse` directly.
- Delete corresponding test assertions for these two methods.

**Task 1.6 — `app/services/conversation_lifecycle.rb`** (~5 min)
- Delete `should_expand_all_mentions?` (lines 216–218). Trivial one-liner delegating to `message.mentions_all?`; replace any call sites with `message.mentions_all?` directly.

**Task 1.7 — `app/models/conversation.rb`** (~10 min)
- Delete the five dead "legacy responded advisors" methods (lines 128–152): `last_advisor_id`, `mark_advisor_spoken`, `advisor_has_responded?`, `mark_advisor_responded`, `all_advisors_responded?`.
- Keep `clear_responded_advisors` (called in `conversations_controller.rb:128`).
- Delete corresponding test assertions for the deleted methods.
- Delete or update the `# Legacy methods for backward compatibility` comment to cover only `clear_responded_advisors`.
- Delete `Conversation.council_meetings` scope (line 56). Only tested, never used in app/.

**Task 1.8 — `app/models/message.rb`** (~5 min)
- Delete `Message#command_name` (lines 81–84). Only tested, never called in app/ code.
- Delete `Message.by_role` scope (line 36). Only tested, never used in app/.
- Delete `Message.with_pending` scope (line 39). Only tested, never used in app/.
- Delete corresponding test assertions for each deleted method/scope.

**Task 1.9 — `app/models/llm_model.rb`** (~10 min)
- Delete `LLMModel.available` scope (line 17). Alias for `enabled`; only used in one test.
- Delete `LLMModel.deprecated` scope (line 18). Only tested, never used in app/.
- Delete `LLMModel.soft_deleted` scope (line 19). Only tested, never used in app/.
- Delete `LLMModel.paid` scope (line 21). Only tested, never used in app/.
- Delete `LLMModel#api` method (lines 44–46). Only called inside `sync_from_ruby_llm!` which is itself dead.
- Delete `LLMModel#sync_from_ruby_llm!` (lines 49–72). Never called in app/ code.
- Delete corresponding test assertions for deleted scopes/methods.

**Task 1.10 — `app/models/advisor.rb`** (~10 min)
- Delete `Advisor.global` scope (line 24). Only tested, never used in app/.
- Delete `Advisor.custom` scope (line 25). Only tested, never used in app/.
- Delete `Advisor.for_space` scope (line 26). Only tested, never used in app/.
- Delete `Advisor.scribes` scope (line 27). Only tested, never used in app/.
- Delete `Advisor.non_scribes` scope (line 28). Only tested, never used in app/ (app uses `where(is_scribe: false)` directly).
- Delete corresponding test assertions for each deleted scope.

**Task 1.11 — `app/models/account.rb`** (~5 min)
- Delete `Account.with_global_advisors` scope (line 24). Only tested, never used in app/.
- Delete corresponding test assertion.

**Task 1.12 — `app/models/memory.rb`** (~15 min)
- Delete `Memory.create_primary_summary!` (lines 141–153). Never called in app/.
- Delete `Memory.create_conversation_notes!` (lines 171–183). Never called in app/.
- Delete `Memory#set_metadata` (line 90–93). Never called in app/.
- Delete `Memory#move_to!` (lines 74–76). Never called in app/.
- Delete `Memory#metadata_value` (lines 85–88). Never called in app/.
- Delete `Memory#track_changes_for_versioning` callback + `before_update` registration (lines 237–240). Explicitly empty no-op.
- Delete corresponding test assertions for each deleted method/callback.

**Task 1.13 — `app/models/space.rb`** (~5 min)
- Delete `Space#find_or_create_scribe_advisor` (lines 26–28). The alias comment says "for backward compatibility" but it's never called anywhere.

**Task 1.14 — `app/models/council.rb`** (~5 min)
- Delete `Council#has_scribe?` (lines 35–37). Never called in app/.

**Task 1.15 — `app/models/usage_record.rb`** (~5 min)
- Delete `UsageRecord.by_provider`, `.by_model`, `.recorded_since`, `.recorded_before` scopes. All only tested, never used in app/.
- Delete corresponding test assertions.

**Task 1.16 — `app/jobs/generate_advisor_response_job.rb`** (~10 min)
- Delete `calculate_cost_from_tokens` (lines 136–150). Uses hardcoded Anthropic-only rates that bypass the model's stored pricing. Usage is already tracked by `AI::Client#track_usage`.
- Audit whether `create_usage_record_from_response` (lines 116–134) is also dead or duplicating `AI::Client#track_usage`. If confirmed duplicate: delete `create_usage_record_from_response` and its call site too. `[SKIP if unsure — confirm double-tracking first]`

---

### Section 2 — Simplifications

**Task 2.1 — Eliminate redundant command routing in `MessagesController`** (~15 min)
- File: `app/controllers/messages_controller.rb`
- The controller has a private `handle_command` that calls `lifecycle.user_posted_message(@message)`, which itself re-parses commands. The controller could call `lifecycle.user_posted_message(@message)` for both command and non-command messages.
- Merge the command branch: remove the controller's `handle_command` method and call `lifecycle.user_posted_message(@message)` uniformly in `create`.
- `[SKIP if unsure — verify that lifecycle handles both paths correctly with tests before deleting]`

**Task 2.2 — Extract duplicated space-validation logic** (~10 min)
- Files: `app/libs/ai/context_builders/base_context_builder.rb` and `app/libs/ai/context_builders/conversation_context_builder.rb`
- `BaseContextBuilder#validate_space!` and `ConversationContextBuilder#validate_space_context!` are nearly identical. After Task 1.2 deletes the base version (which is dead), rename `validate_space_context!` to `validate_space!` in `ConversationContextBuilder` for consistency with base class naming conventions.

**Task 2.3 — Remove fallback scribe creation in `GenerateConversationSummaryJob`** (~10 min)
- File: `app/jobs/generate_conversation_summary_job.rb` lines 170–187
- Every `Space` already creates a Scribe advisor in an `after_create` callback. The fallback `find_or_create_scribe_advisor` in the job is a code smell that can create orphaned advisors.
- Replace with a direct lookup that raises/logs clearly if no scribe is found, rather than silently creating one.
- `[SKIP if unsure — add a test to confirm Space always has a scribe before removing the fallback]`

---

### Section 3 — Clarity Fixes

**Task 3.1 — Fix stale comment in `application_helper.rb`** (~2 min)
- File: `app/helpers/application_helper.rb` line 19
- Comment references removed modes: "On Demand, Silent, Round Robin, and Moderated". Update to reflect current modes: Open, Consensus, Brainstorming.

**Task 3.2 — Remove commented-out rescue block in `AI::Client`** (~2 min)
- File: `app/libs/ai/client.rb` lines 83–85
- Remove the dead `# rescue StandardError => e` commented-out block.

**Task 3.3 — Remove misleading backward-compat comment in `space.rb`** (~2 min)
- File: `app/models/space.rb`
- After Task 1.13 deletes `find_or_create_scribe_advisor`, remove the accompanying comment entirely.

**Task 3.4 — Update or remove legacy comment in `conversation.rb`** (~2 min)
- File: `app/models/conversation.rb` around line 127
- After Task 1.7 deletes five dead methods, update the `# Legacy methods for backward compatibility` comment to describe only `clear_responded_advisors`, or remove it entirely.

**Task 3.5 — Remove no-op callback comment in `memory.rb`** (~2 min)
- File: `app/models/memory.rb` around line 237
- After Task 1.12 deletes `track_changes_for_versioning`, remove the accompanying "hook for future auto-versioning" comment.

**Task 3.6 — Fix double blank lines / leading blank lines in tool files** (~2 min)
- Files: `app/libs/ai/tools/conversations/ask_advisor_tool.rb`, `finish_conversation_tool.rb`, `summarize_conversation_tool.rb`, `app/libs/ai/context_builders/scribe_context_builder.rb` (deleted by Task 1.3).
- Remove extra leading blank lines at top of files.

**Task 3.7 — Investigate `adhoc` route** (~5 min)
- File: `config/routes.rb` line 76 — `get :adhoc` has no corresponding `ConversationsController#adhoc` action.
- Confirm: if action does not exist, remove the route. `[SKIP if unsure — search git history for the action first]`

---

## Verification
- Run the full test suite after each task group: `bin/rails test`
- Confirm no `NameError` / `NoMethodError` in boot: `bin/rails runner 'puts Rails.application.eager_load!'`
- For Task 1.16 (double usage tracking): add a test that asserts only one `UsageRecord` is created per advisor response before deleting any tracking code.
- For Task 2.1 (command routing): run `bin/rails test test/controllers/messages_controller_test.rb` before and after.
- For Task 2.3 (scribe fallback): run `bin/rails test test/jobs/generate_conversation_summary_job_test.rb`.
- Git diff each task to keep individual PRs small and reviewable.

## Doc impact
- `doc impact: none` — this is pure dead-code removal with no behavior change.

## Rollback
- Each task is an independent atomic deletion. Rollback is `git revert <commit>` per task.
- No migrations; no schema changes; nothing to undo in the DB.
