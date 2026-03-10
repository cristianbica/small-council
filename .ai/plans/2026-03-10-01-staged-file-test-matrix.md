# Plan 01: Staged File Test Matrix

- Date: `2026-03-10`
- Scope source: `git diff --cached --name-status` and `git diff --cached --numstat` (snapshot count: `159` staged files).
- Goal: execute a controlled, area-batched test strategy for the staged refactor with per-file accountability.
- Non-goals: implementing product code, modifying git state, deleting files in this plan.

## Execution Order and Batching Strategy

1. Batch A - `AI Docs/Workflows` (32 files): verify process artifacts, references, and naming consistency before runtime work.
2. Batch B - `Config/DB` (6 files): run route + migration sanity early to avoid false negatives in later test batches.
3. Batch C - `Backend Controllers/Models` (12 files): run controller/model/unit tests per file, then area sweep.
4. Batch D - `AI Runtime Libs` (47 files): execute lib tests file-by-file (matching suites), then full AI runtime sweep.
5. Batch E - `Views/Layouts/JS` (30 files): run UI/system/controller regression for chat, composer, and modal flows.
6. Batch F - `Tests/Fixtures` (32 files): execute newly added/modified tests file-by-file, then full staged aggregate run.

Per-file run order inside each batch:
- New files (`A`) first (establish baseline), then modified (`M`), then renames (`R`), then deletions (`D`) validated by reference scans + regressions.
- For each file: run nearest targeted test command immediately after validation command(s), log pass/fail and blockers in a run sheet.

## Coverage Target (Changed/New Lines)

- Target: `100%` coverage of changed/new lines in the staged diff (all `A` and added lines in `M/R`).
- Verification method:
- Generate changed line map: `git diff --cached -U0 --no-color > tmp/staged.patch`.
- Run staged test matrix with coverage enabled (SimpleCov): `COVERAGE=true bin/rails test ...` in batch order.
- Compare changed line map against coverage report (`coverage/.resultset.json` or equivalent) via a line-hit script/checklist; require zero uncovered changed lines before completion.
- Keep explicit exceptions list empty; if any line cannot be covered, block completion until design/test approach is updated.

## Per-File Matrix

### AI Docs/Workflows (32 files)

| File | Status | Delta (+/-) | Short Summary | What To Test |
| --- | --- | --- | --- | --- |
| `.ai/HUMANS.md` | `M` | `1/1` | Revise AI process/docs file `HUMANS.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/MEMORY.md` | `M` | `2/0` | Revise AI process/docs file `MEMORY.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/RULES.md` | `A` | `56/0` | Add new ai doc/workflow `RULES.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/agents/builder.md` | `M` | `1/0` | Revise AI process/docs file `builder.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/agents/conductor.md` | `M` | `4/1` | Revise AI process/docs file `conductor.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/agents/forger.md` | `M` | `4/1` | Revise AI process/docs file `forger.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/agents/planner.md` | `M` | `4/2` | Revise AI process/docs file `planner.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/agents/validator.md` | `M` | `1/0` | Revise AI process/docs file `validator.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/ai-diagram.md` | `A` | `288/0` | Add new ai doc/workflow `ai-diagram.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/features/README.md` | `M` | `1/0` | Revise AI process/docs file `README.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/features/advisors.md` | `M` | `7/1` | Revise AI process/docs file `advisors.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/features/ai-integration.md` | `M` | `9/0` | Revise AI process/docs file `ai-integration.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/features/conversations.md` | `M` | `19/23` | Revise AI process/docs file `conversations.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/features/councils.md` | `M` | `6/3` | Revise AI process/docs file `councils.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/features/form-fillers.md` | `A` | `133/0` | Add new ai doc/workflow `form-fillers.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/docs/overview.md` | `M` | `4/2` | Revise AI process/docs file `overview.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-06-01-tools-approval.md` | `A` | `357/0` | Add new ai doc/workflow `2026-03-06-01-tools-approval.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-06-02-ruby-llm-tool-approval-investigation.md` | `A` | `300/0` | Add new ai doc/workflow `2026-03-06-02-ruby-llm-tool-approval-investigation.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-06-03-ai-simplification-investigation.md` | `A` | `353/0` | Add new ai doc/workflow `2026-03-06-03-ai-simplification-investigation.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-06-04-ai-tasks-agents-runner-refactor-plan.md` | `A` | `649/0` | Add new ai doc/workflow `2026-03-06-04-ai-tasks-agents-runner-refactor-plan.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-06-05-ai-runtime-short-plan.md` | `A` | `281/0` | Add new ai doc/workflow `2026-03-06-05-ai-runtime-short-plan.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-07-01-form-filler-flow-advisor-profile.md` | `A` | `247/0` | Add new ai doc/workflow `2026-03-07-01-form-filler-flow-advisor-profile.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-07-02-form-filler-simplification.md` | `A` | `192/0` | Add new ai doc/workflow `2026-03-07-02-form-filler-simplification.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-08-01-conversation-ai-runtime-slice.md` | `A` | `106/0` | Add new ai doc/workflow `2026-03-08-01-conversation-ai-runtime-slice.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-08-02-ruby-llm-native-tools-refactor.md` | `A` | `106/0` | Add new ai doc/workflow `2026-03-08-02-ruby-llm-native-tools-refactor.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-08-03-conversation-runtime-design.md` | `A` | `434/0` | Add new ai doc/workflow `2026-03-08-03-conversation-runtime-design.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-08-04-conversation-runtime-implementation.md` | `A` | `226/0` | Add new ai doc/workflow `2026-03-08-04-conversation-runtime-implementation.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-09-01-REFACTOR-chat-ui-ai-integration.md` | `A` | `316/0` | Add new ai doc/workflow `2026-03-09-01-REFACTOR-chat-ui-ai-integration.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-09-02-message-create-failure-composer-frame.md` | `A` | `29/0` | Add new ai doc/workflow `2026-03-09-02-message-create-failure-composer-frame.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/plans/2026-03-09-03-message-interactions-refactor.md` | `A` | `7/0` | Add new ai doc/workflow `2026-03-09-03-message-interactions-refactor.md` to support staged refactor path. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/workflows/change.md` | `M` | `2/1` | Revise AI process/docs file `change.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |
| `.ai/workflows/investigate.md` | `M` | `2/2` | Revise AI process/docs file `investigate.md` for updated workflow and governance. | Manual markdown/link sanity; ensure workflow references resolve; no product runtime test. |

### Backend Controllers/Models (12 files)

| File | Status | Delta (+/-) | Short Summary | What To Test |
| --- | --- | --- | --- | --- |
| `app/controllers/advisors_controller.rb` | `M` | `0/22` | Modify controller `advisors_controller.rb` to align behavior with the refactor slice. | Run controller tests for `advisors_controller` plus related integration flow (`bin/rails test test/controllers`). |
| `app/controllers/application_controller.rb` | `M` | `5/0` | Modify controller `application_controller.rb` to align behavior with the refactor slice. | Run controller tests for `application_controller` plus related integration flow (`bin/rails test test/controllers`). |
| `app/controllers/conversations_controller.rb` | `M` | `3/13` | Modify controller `conversations_controller.rb` to align behavior with the refactor slice. | Run controller tests for `conversations_controller` plus related integration flow (`bin/rails test test/controllers`). |
| `app/controllers/councils_controller.rb` | `M` | `0/32` | Modify controller `councils_controller.rb` to align behavior with the refactor slice. | Run controller tests for `councils_controller` plus related integration flow (`bin/rails test test/controllers`). |
| `app/controllers/form_fillers_controller.rb` | `A` | `50/0` | Add new controller `form_fillers_controller.rb` to support staged refactor path. | Run controller tests for `form_fillers_controller` plus related integration flow (`bin/rails test test/controllers`). |
| `app/controllers/messages_controller.rb` | `M` | `14/15` | Modify controller `messages_controller.rb` to align behavior with the refactor slice. | Run controller tests for `messages_controller` plus related integration flow (`bin/rails test test/controllers`). |
| `app/jobs/ai_runner_job.rb` | `A` | `9/0` | Add new job `ai_runner_job.rb` to support staged refactor path. | Run `bin/rails test test/jobs` and AI runner integration tests for enqueue/perform behavior. |
| `app/models/advisor.rb` | `M` | `3/0` | Modify model `advisor.rb` to align behavior with the refactor slice. | Run model-focused tests touching `advisor` and conversation/message data integrity checks. |
| `app/models/conversation.rb` | `M` | `3/2` | Modify model `conversation.rb` to align behavior with the refactor slice. | Run model-focused tests touching `conversation` and conversation/message data integrity checks. |
| `app/models/conversation_participant.rb` | `M` | `1/0` | Modify model `conversation_participant.rb` to align behavior with the refactor slice. | Run model-focused tests touching `conversation_participant` and conversation/message data integrity checks. |
| `app/models/message.rb` | `M` | `44/1` | Modify model `message.rb` to align behavior with the refactor slice. | Run model-focused tests touching `message` and conversation/message data integrity checks. |
| `app/models/model_interaction.rb` | `M` | `7/10` | Modify model `model_interaction.rb` to align behavior with the refactor slice. | Run model-focused tests touching `model_interaction` and conversation/message data integrity checks. |

### AI Runtime Libs (47 files)

| File | Status | Delta (+/-) | Short Summary | What To Test |
| --- | --- | --- | --- | --- |
| `app/libs/ai.rb` | `A` | `134/0` | Add new file `ai.rb` to support staged refactor path. | Run nearest targeted tests plus area regression suite. |
| `app/libs/ai/agents/advisor_agent.rb` | `A` | `19/0` | Add new runtime lib `advisor_agent.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `advisor_agent`. |
| `app/libs/ai/agents/base_agent.rb` | `A` | `22/0` | Add new runtime lib `base_agent.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `base_agent`. |
| `app/libs/ai/agents/text_writer_agent.rb` | `A` | `9/0` | Add new runtime lib `text_writer_agent.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `text_writer_agent`. |
| `app/libs/ai/client.rb` | `M` | `20/0` | Modify AI client entrypoint to integrate split chat/runtime architecture. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `client`. |
| `app/libs/ai/client/chat.rb` | `A` | `46/0` | Add new runtime lib `chat.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `chat`. |
| `app/libs/ai/contexts/base_context.rb` | `A` | `29/0` | Add new runtime lib `base_context.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `base_context`. |
| `app/libs/ai/contexts/conversation_context.rb` | `A` | `39/0` | Add new runtime lib `conversation_context.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `conversation_context`. |
| `app/libs/ai/contexts/space_context.rb` | `A` | `19/0` | Add new runtime lib `space_context.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `space_context`. |
| `app/libs/ai/handlers/base_handler.rb` | `A` | `18/0` | Add new runtime lib `base_handler.rb` to support staged refactor path. | Run handler tests under `test/libs/ai/handlers/**` and message rendering assertions. |
| `app/libs/ai/handlers/conversation_response_handler.rb` | `A` | `32/0` | Add new runtime lib `conversation_response_handler.rb` to support staged refactor path. | Run handler tests under `test/libs/ai/handlers/**` and message rendering assertions. |
| `app/libs/ai/handlers/turbo_form_filler_handler.rb` | `A` | `40/0` | Add new runtime lib `turbo_form_filler_handler.rb` to support staged refactor path. | Run handler tests under `test/libs/ai/handlers/**` and message rendering assertions. |
| `app/libs/ai/prompts/agents/advisor.erb` | `A` | `45/0` | Add new runtime lib `advisor.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `advisor.erb`. |
| `app/libs/ai/prompts/agents/text_writer.erb` | `A` | `26/0` | Add new runtime lib `text_writer.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `text_writer.erb`. |
| `app/libs/ai/prompts/conversations/brainstorming_moderator.erb` | `A` | `37/0` | Add new runtime lib `brainstorming_moderator.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `brainstorming_moderator.erb`. |
| `app/libs/ai/prompts/conversations/consensus_moderator.erb` | `A` | `32/0` | Add new runtime lib `consensus_moderator.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `consensus_moderator.erb`. |
| `app/libs/ai/prompts/conversations/drilldown.erb` | `A` | `30/0` | Add new runtime lib `drilldown.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `drilldown.erb`. |
| `app/libs/ai/prompts/conversations/final_synthesis.erb` | `A` | `22/0` | Add new runtime lib `final_synthesis.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `final_synthesis.erb`. |
| `app/libs/ai/prompts/conversations/force_conclusion.erb` | `A` | `17/0` | Add new runtime lib `force_conclusion.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `force_conclusion.erb`. |
| `app/libs/ai/prompts/conversations/force_synthesis.erb` | `A` | `18/0` | Add new runtime lib `force_synthesis.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `force_synthesis.erb`. |
| `app/libs/ai/prompts/tasks/advisor_profile.erb` | `A` | `8/0` | Add new runtime lib `advisor_profile.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `advisor_profile.erb`. |
| `app/libs/ai/prompts/tasks/council_profile.erb` | `A` | `10/0` | Add new runtime lib `council_profile.erb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `council_profile.erb`. |
| `app/libs/ai/result.rb` | `A` | `22/0` | Add new runtime lib `result.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `result`. |
| `app/libs/ai/runner.rb` | `A` | `103/0` | Add new runtime lib `runner.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `runner`. |
| `app/libs/ai/runtimes/brainstorming_conversation_runtime.rb` | `A` | `40/0` | Add new runtime lib `brainstorming_conversation_runtime.rb` to support staged refactor path. | Run matching runtime tests under `test/libs/ai/runtimes/**` plus `test/ai/runner_test.rb`. |
| `app/libs/ai/runtimes/consensus_conversation_runtime.rb` | `A` | `40/0` | Add new runtime lib `consensus_conversation_runtime.rb` to support staged refactor path. | Run matching runtime tests under `test/libs/ai/runtimes/**` plus `test/ai/runner_test.rb`. |
| `app/libs/ai/runtimes/conversation_runtime.rb` | `A` | `83/0` | Add new runtime lib `conversation_runtime.rb` to support staged refactor path. | Run matching runtime tests under `test/libs/ai/runtimes/**` plus `test/ai/runner_test.rb`. |
| `app/libs/ai/runtimes/open_conversation_runtime.rb` | `A` | `20/0` | Add new runtime lib `open_conversation_runtime.rb` to support staged refactor path. | Run matching runtime tests under `test/libs/ai/runtimes/**` plus `test/ai/runner_test.rb`. |
| `app/libs/ai/schemas/advisor_profile_schema.rb` | `A` | `29/0` | Add new runtime lib `advisor_profile_schema.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `advisor_profile_schema`. |
| `app/libs/ai/schemas/council_profile_schema.rb` | `A` | `25/0` | Add new runtime lib `council_profile_schema.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `council_profile_schema`. |
| `app/libs/ai/tasks/base_task.rb` | `A` | `52/0` | Add new runtime lib `base_task.rb` to support staged refactor path. | Run task tests under `test/libs/ai/tasks/**`; verify tool call + response composition paths. |
| `app/libs/ai/tasks/respond_task.rb` | `A` | `117/0` | Add new runtime lib `respond_task.rb` to support staged refactor path. | Run task tests under `test/libs/ai/tasks/**`; verify tool call + response composition paths. |
| `app/libs/ai/tasks/text_task.rb` | `A` | `32/0` | Add new runtime lib `text_task.rb` to support staged refactor path. | Run task tests under `test/libs/ai/tasks/**`; verify tool call + response composition paths. |
| `app/libs/ai/tools/abstract_tool.rb` | `A` | `32/0` | Add new runtime lib `abstract_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/advisors/create_advisor_tool.rb` | `A` | `43/0` | Add new runtime lib `create_advisor_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/advisors/fetch_advisor_tool.rb` | `A` | `44/0` | Add new runtime lib `fetch_advisor_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/advisors/list_advisors_tool.rb` | `A` | `61/0` | Add new runtime lib `list_advisors_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/advisors/update_advisor_tool.rb` | `A` | `49/0` | Add new runtime lib `update_advisor_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/internal/list_conversations_tool.rb` | `M` | `0/1` | Modify runtime lib `list_conversations_tool.rb` to align behavior with the refactor slice. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/internal/query_conversations_tool.rb` | `M` | `0/1` | Modify runtime lib `query_conversations_tool.rb` to align behavior with the refactor slice. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/memories/create_memory_tool.rb` | `A` | `50/0` | Add new runtime lib `create_memory_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/memories/fetch_memory_tool.rb` | `A` | `43/0` | Add new runtime lib `fetch_memory_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/memories/list_memories_tool.rb` | `A` | `60/0` | Add new runtime lib `list_memories_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/memories/search_memories_tool.rb` | `A` | `59/0` | Add new runtime lib `search_memories_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/tools/memories/update_memory_tool.rb` | `A` | `53/0` | Add new runtime lib `update_memory_tool.rb` to support staged refactor path. | Run matching AI tools tests under `test/libs/ai/tools/**` and integration calls through runner. |
| `app/libs/ai/trackers/model_interaction_tracker.rb` | `A` | `261/0` | Add new runtime lib `model_interaction_tracker.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `model_interaction_tracker`. |
| `app/libs/ai/trackers/usage_tracker.rb` | `A` | `53/0` | Add new runtime lib `usage_tracker.rb` to support staged refactor path. | Run AI library tests (`test/libs/ai_test.rb`, `test/ai/runner_test.rb`) and impacted unit suites for `usage_tracker`. |

### Views/Layouts/JS (30 files)

| File | Status | Delta (+/-) | Short Summary | What To Test |
| --- | --- | --- | --- | --- |
| `app/javascript/controllers/conversation_controller.js` | `M` | `10/0` | Modify controller `conversation_controller.js` to align behavior with the refactor slice. | Run JS controller/system flow checks for modal/composer interactions; verify Turbo frame behavior manually. |
| `app/javascript/controllers/form_filler_controller.js` | `A` | `56/0` | Add new controller `form_filler_controller.js` to support staged refactor path. | Run JS controller/system flow checks for modal/composer interactions; verify Turbo frame behavior manually. |
| `app/javascript/controllers/page_modal_controller.js` | `A` | `56/0` | Add new controller `page_modal_controller.js` to support staged refactor path. | Run JS controller/system flow checks for modal/composer interactions; verify Turbo frame behavior manually. |
| `app/views/advisors/_form.html.erb` | `M` | `97/139` | Modify view `_form.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/advisors/index.html.erb` | `M` | `4/4` | Modify view `index.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/shared/_chat.html.erb -> app/views/conversations/_chat.html.erb` | `R` | `3/57` | Move view partial from `app/views/shared/_chat.html.erb` to `app/views/conversations/_chat.html.erb` with namespace realignment. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/conversations/_composer.html.erb` | `A` | `47/0` | Add new view `_composer.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/conversations/_message.html.erb` | `A` | `69/0` | Add new view `_message.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/conversations/_sidebar_conversation_item.html.erb` | `A` | `39/0` | Add new view `_sidebar_conversation_item.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/conversations/index.html.erb` | `M` | `1/5` | Modify view `index.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/conversations/show.html.erb` | `M` | `6/108` | Modify view `show.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/councils/_form.html.erb` | `M` | `27/71` | Modify view `_form.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/councils/show.html.erb` | `M` | `1/5` | Modify view `show.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/form_fillers/_error.html.erb` | `A` | `8/0` | Add new view `_error.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/form_fillers/_form.html.erb` | `A` | `37/0` | Add new view `_form.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/form_fillers/_pending.html.erb` | `A` | `19/0` | Add new view `_pending.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/form_fillers/_result.html.erb` | `A` | `8/0` | Add new view `_result.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/form_fillers/new.html.erb` | `A` | `15/0` | Add new view `new.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/layouts/application.html.erb` | `M` | `9/7` | Modify view `application.html.erb` to align behavior with the refactor slice. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/layouts/conversation.html.erb` | `D` | `0/60` | Delete legacy view `conversation.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/layouts/inner/_default.html.erb` | `A` | `3/0` | Add new view `_default.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/layouts/inner/_fullscreen.html.erb` | `A` | `3/0` | Add new view `_fullscreen.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/layouts/turbo_rails/frame.html+modal.erb` | `A` | `15/0` | Add new view `frame.html+modal.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |
| `app/views/messages/_interactions_content.html.erb` | `D` | `0/23` | Delete legacy view `_interactions_content.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/messages/_interactions_count.html.erb` | `D` | `0/1` | Delete legacy view `_interactions_count.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/messages/_interactions_frame.html.erb` | `D` | `0/3` | Delete legacy view `_interactions_frame.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/messages/_interactions_list.html.erb` | `D` | `0/6` | Delete legacy view `_interactions_list.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/messages/_message.html.erb` | `D` | `0/153` | Delete legacy view `_message.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/messages/_message_thread.html.erb` | `D` | `0/15` | Delete legacy view `_message_thread.html.erb` replaced by new flow/components. | Run conversation/message UI regression tests to confirm deleted partials are no longer referenced. |
| `app/views/messages/interactions.html.erb` | `A` | `21/0` | Add new view `interactions.html.erb` to support staged refactor path. | Run conversation/council/advisor view regression (system + controller tests); validate Turbo rendering paths. |

### Config/DB (6 files)

| File | Status | Delta (+/-) | Short Summary | What To Test |
| --- | --- | --- | --- | --- |
| `Gemfile.lock` | `M` | `1/1` | Modify file `Gemfile.lock` to align behavior with the refactor slice. | Run `bundle check`; execute targeted test batches to confirm dependency lock consistency. |
| `config/importmap.rb` | `M` | `2/2` | Modify config/db `importmap.rb` to align behavior with the refactor slice. | Run smoke boot (`bin/rails runner`) plus related tests to verify config changes load correctly. |
| `config/locales/en.yml` | `M` | `29/0` | Modify config/db `en.yml` to align behavior with the refactor slice. | Run smoke boot (`bin/rails runner`) plus related tests to verify config changes load correctly. |
| `config/routes.rb` | `M` | `2/13` | Adjust routing graph for new conversation/form-filler endpoints. | Run route recognition checks and controller tests for newly routed endpoints. |
| `db/migrate/20260310120000_add_tool_calls_to_messages.rb` | `A` | `5/0` | Add new config/db `20260310120000_add_tool_calls_to_messages.rb` to support staged refactor path. | Run migration up/down in test DB and full AI/message test slice after schema change. |
| `db/schema.rb` | `M` | `2/1` | Refresh schema snapshot to include staged migration effects. | Run `bin/rails db:test:prepare` and staged test batches to ensure schema parity. |

### Tests/Fixtures (32 files)

| File | Status | Delta (+/-) | Short Summary | What To Test |
| --- | --- | --- | --- | --- |
| `test/ai/runner_test.rb` | `A` | `8/0` | Add new test `runner_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/ai/runner_test.rb`) and ensure deterministic pass. |
| `test/ai/unit/context_builders/base_context_builder_test.rb` | `M` | `18/6` | Modify test `base_context_builder_test.rb` to align behavior with the refactor slice. | Execute this test file directly (`bin/rails test test/ai/unit/context_builders/base_context_builder_test.rb`) and ensure deterministic pass. |
| `test/ai/unit/context_builders/conversation_context_builder_test.rb` | `M` | `5/2` | Modify test `conversation_context_builder_test.rb` to align behavior with the refactor slice. | Execute this test file directly (`bin/rails test test/ai/unit/context_builders/conversation_context_builder_test.rb`) and ensure deterministic pass. |
| `test/ai/unit/tools/internal/list_advisors_tool_test.rb` | `M` | `2/1` | Modify test `list_advisors_tool_test.rb` to align behavior with the refactor slice. | Execute this test file directly (`bin/rails test test/ai/unit/tools/internal/list_advisors_tool_test.rb`) and ensure deterministic pass. |
| `test/ai/unit/tools/internal/list_conversations_tool_test.rb` | `M` | `4/2` | Modify test `list_conversations_tool_test.rb` to align behavior with the refactor slice. | Execute this test file directly (`bin/rails test test/ai/unit/tools/internal/list_conversations_tool_test.rb`) and ensure deterministic pass. |
| `test/controllers/advisors_controller_comprehensive_test.rb` | `M` | `0/68` | Modify controller `advisors_controller_comprehensive_test.rb` to align behavior with the refactor slice. | Execute this test file directly (`bin/rails test test/controllers/advisors_controller_comprehensive_test.rb`) and ensure deterministic pass. |
| `test/controllers/councils_controller_generate_description_test.rb` | `D` | `0/137` | Delete legacy controller `councils_controller_generate_description_test.rb` replaced by new flow/components. | Execute this test file directly (`bin/rails test test/controllers/councils_controller_generate_description_test.rb`) and ensure deterministic pass. |
| `test/controllers/councils_controller_test.rb` | `M` | `7/0` | Modify controller `councils_controller_test.rb` to align behavior with the refactor slice. | Execute this test file directly (`bin/rails test test/controllers/councils_controller_test.rb`) and ensure deterministic pass. |
| `test/controllers/form_fillers_controller_test.rb` | `A` | `136/0` | Add new controller `form_fillers_controller_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/controllers/form_fillers_controller_test.rb`) and ensure deterministic pass. |
| `test/fixtures/advisors.yml` | `A` | `15/0` | Add new test `advisors.yml` to support staged refactor path. | Run tests that consume this fixture domain; verify no fixture key collisions or FK mismatches. |
| `test/fixtures/conversation_participants.yml` | `A` | `19/0` | Add new test `conversation_participants.yml` to support staged refactor path. | Run tests that consume this fixture domain; verify no fixture key collisions or FK mismatches. |
| `test/fixtures/conversations.yml` | `A` | `28/0` | Add new test `conversations.yml` to support staged refactor path. | Run tests that consume this fixture domain; verify no fixture key collisions or FK mismatches. |
| `test/fixtures/council_advisors.yml` | `A` | `9/0` | Add new test `council_advisors.yml` to support staged refactor path. | Run tests that consume this fixture domain; verify no fixture key collisions or FK mismatches. |
| `test/fixtures/councils.yml` | `A` | `15/0` | Add new test `councils.yml` to support staged refactor path. | Run tests that consume this fixture domain; verify no fixture key collisions or FK mismatches. |
| `test/fixtures/messages.yml` | `A` | `43/0` | Add new test `messages.yml` to support staged refactor path. | Run tests that consume this fixture domain; verify no fixture key collisions or FK mismatches. |
| `test/libs/ai/handlers/conversation_response_handler_test.rb` | `A` | `41/0` | Add new runtime lib `conversation_response_handler_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/handlers/conversation_response_handler_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/runtimes/brainstorming_conversation_runtime_test.rb` | `A` | `37/0` | Add new runtime lib `brainstorming_conversation_runtime_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/runtimes/brainstorming_conversation_runtime_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/runtimes/consensus_conversation_runtime_test.rb` | `A` | `74/0` | Add new runtime lib `consensus_conversation_runtime_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/runtimes/consensus_conversation_runtime_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/runtimes/conversation_runtime_test.rb` | `A` | `87/0` | Add new runtime lib `conversation_runtime_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/runtimes/conversation_runtime_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/runtimes/open_conversation_runtime_test.rb` | `A` | `53/0` | Add new runtime lib `open_conversation_runtime_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/runtimes/open_conversation_runtime_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tasks/respond_task_test.rb` | `A` | `88/0` | Add new runtime lib `respond_task_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tasks/respond_task_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/abstract_tool_test.rb` | `A` | `56/0` | Add new runtime lib `abstract_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/abstract_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/advisors/create_advisor_tool_test.rb` | `A` | `89/0` | Add new runtime lib `create_advisor_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/advisors/create_advisor_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/advisors/fetch_advisor_tool_test.rb` | `A` | `64/0` | Add new runtime lib `fetch_advisor_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/advisors/fetch_advisor_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/advisors/list_advisors_tool_test.rb` | `A` | `101/0` | Add new runtime lib `list_advisors_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/advisors/list_advisors_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/advisors/update_advisor_tool_test.rb` | `A` | `108/0` | Add new runtime lib `update_advisor_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/advisors/update_advisor_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/memories/create_memory_tool_test.rb` | `A` | `80/0` | Add new runtime lib `create_memory_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/memories/create_memory_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/memories/fetch_memory_tool_test.rb` | `A` | `65/0` | Add new runtime lib `fetch_memory_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/memories/fetch_memory_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/memories/list_memories_tool_test.rb` | `A` | `112/0` | Add new runtime lib `list_memories_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/memories/list_memories_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/memories/search_memories_tool_test.rb` | `A` | `116/0` | Add new runtime lib `search_memories_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/memories/search_memories_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai/tools/memories/update_memory_tool_test.rb` | `A` | `102/0` | Add new runtime lib `update_memory_tool_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai/tools/memories/update_memory_tool_test.rb`) and ensure deterministic pass. |
| `test/libs/ai_test.rb` | `A` | `156/0` | Add new test `ai_test.rb` to support staged refactor path. | Execute this test file directly (`bin/rails test test/libs/ai_test.rb`) and ensure deterministic pass. |

## Verification Commands (Planned)

- `git diff --cached --name-status` (scope lock for file list)
- `git diff --cached --numstat` (change magnitude context per file)
- `bin/rails test test/controllers test/models test/jobs` (backend sweep)
- `bin/rails test test/libs/ai test/ai` (AI runtime sweep)
- `bin/rails test test/system test/integration` (UI/regression sweep where applicable)
- `bin/rails test` (final aggregate confirmation for staged set)

## Doc Impact

- `doc impact`: deferred (handled by Plan 03 after cleanup decisions from Plan 02).
