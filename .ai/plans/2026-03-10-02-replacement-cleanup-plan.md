# Plan 02: Replacement Cleanup Plan

- Date: `2026-03-10`
- Derived from: `.ai/plans/2026-03-10-01-staged-file-test-matrix.md`
- Goal: identify replaced artifacts that can be safely deleted, define proof checks, and execute cleanup with rollback guardrails.
- Non-goals: implementing product features, using git write operations, changing behavior outside staged refactor scope.

## Inputs and Assumptions

- Input snapshot is the 159-file staged set from Plan 01.
- Replacement signals used: `D` (deleted), `R` (renamed/moved), and `A+M` pairs that indicate old/new architecture split.
- Deletion is only approved after reference scans and runtime smoke checks pass.

## Candidate Deletion List

| Candidate | Why It Is Safe Candidate | Proof Checks Required |
| --- | --- | --- |
| `app/views/layouts/conversation.html.erb` | Replaced by inner layout partials + modal frame layout. | `grep -R "layouts/conversation" app config test`; render conversation pages in test/system flow. |
| `app/views/messages/_interactions_content.html.erb` | Interactions rendering consolidated into `app/views/messages/interactions.html.erb`. | `grep -R "_interactions_content" app test`; run interactions endpoint/controller tests. |
| `app/views/messages/_interactions_count.html.erb` | Legacy count partial removed in favor of new interactions view composition. | `grep -R "_interactions_count" app test`; run conversation/message UI regressions. |
| `app/views/messages/_interactions_frame.html.erb` | Legacy frame partial superseded by new Turbo layout strategy. | `grep -R "_interactions_frame" app test`; verify Turbo frame rendering in interactions flow. |
| `app/views/messages/_interactions_list.html.erb` | Legacy list partial replaced by unified interactions template. | `grep -R "_interactions_list" app test`; run message interactions tests. |
| `app/views/messages/_message.html.erb` | Message rendering moved to `app/views/conversations/_message.html.erb`. | `grep -R "messages/_message" app test`; run conversation show/index rendering tests. |
| `app/views/messages/_message_thread.html.erb` | Thread partial replaced by conversation-scoped chat/message partials. | `grep -R "_message_thread" app test`; run conversation thread system tests. |
| `test/controllers/councils_controller_generate_description_test.rb` | Legacy controller behavior removed/replaced by updated councils/form-filler flow. | `grep -R "generate_description" app test`; ensure replacement coverage in current controller tests. |
| `app/views/shared/_chat.html.erb` (renamed) | Moved to `app/views/conversations/_chat.html.erb` (`R070`). | `grep -R "shared/_chat" app test`; run conversation UI regressions and ensure new path is used. |

## Potential Follow-Up Deletion Candidates (Post-Verification)

| Candidate | Trigger to Delete | Proof Checks |
| --- | --- | --- |
| Legacy code paths in `app/libs/ai/client.rb` superseded by `app/libs/ai/client/chat.rb` | Only after call graph confirms no remaining direct legacy client responsibilities. | `grep -R "AI::Client" app test`; inspect runtime entrypoints in `app/libs/ai.rb` and `app/libs/ai/runner.rb`. |
| Legacy councils generation view/controller hooks replaced by form fillers | Only after route/controller/view reference scans show zero usage. | `grep -R "generate_description\|form_filler" app config test`; run councils + form-fillers tests together. |

## Safe Deletion Order

1. Confirm replacement files exist and pass targeted tests (new views/layouts/runtime).
2. Run reference scans for each candidate path; require zero app/test references.
3. Delete leaf partials first (`app/views/messages/_interactions_*`, `_message_thread`).
4. Delete parent/entry partials (`app/views/messages/_message.html.erb`, old shared chat path).
5. Delete legacy layout (`app/views/layouts/conversation.html.erb`) after view/controller sweeps pass.
6. Delete legacy tests only after equivalent or stronger replacement coverage is confirmed.
7. Run area sweeps (`controllers`, `views/system`, `libs/ai`) and final aggregate test run.

## Proof Checks and Commands (Read-Only + Validation)

- `git diff --cached --name-status`
- `git diff --cached --summary`
- `grep -R "<symbol-or-path>" app config test`
- `bin/rails test test/controllers test/models test/jobs`
- `bin/rails test test/libs/ai test/ai`
- `bin/rails test test/system test/integration`

## Rollback Guardrails (No Git Write Ops)

- Before any delete action, save a filesystem backup copy under `tmp/refactor-backups/<timestamp>/...`.
- Export a pre-cleanup patch snapshot: `git diff --cached --no-color > tmp/refactor-backups/<timestamp>/staged.patch`.
- Keep a deletion ledger file (path, reason, proof command output, timestamp).
- If regression occurs, restore from backup copies only (no `git restore`, no `git checkout`, no reset operations).
- Stop cleanup immediately on first unresolved failing test and re-run reference scans before continuing.

## Exit Criteria

- Every deleted or moved legacy path has zero references in `app/`, `config/`, and `test/`.
- Replacement tests pass for each cleaned area.
- Final aggregate test run passes.
- Cleanup ledger is complete.

## Doc Impact

- `doc impact`: deferred to Plan 03 (final docs update mapping and acceptance).
