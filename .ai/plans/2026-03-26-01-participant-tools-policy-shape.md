# Plan: Participant Tools Policy Shape (ref + policy)

## Intake Summary
- Type: feature/refactor
- Goal: change `ConversationParticipant.tools` data shape from array of refs to array of policy hashes:
  - `{ ref: "internet/browse", policy: "allow" }`
  - `{ ref: "memories/create", policy: "deny" }`
- Constraint: do not implement ask-policy behavior now; only support `allow|deny` representation and current runtime behavior.
- Constraint: do not use `_refs` suffix in method names.
- Constraint: `tools` and `effective_tools` must return the same structure type (policy-hash array).

## Acceptance Criteria
- [ ] `ConversationParticipant.tools` persists as array of hashes with keys `ref` and `policy`.
- [ ] `ConversationParticipant.effective_tools` returns the same policy-hash structure as `tools`.
- [ ] Policies are validated (`allow` and `deny` only), refs must exist in tool registry.
- [ ] Existing rows saved as string arrays remain readable/compatible (coerced in model logic).
- [ ] AI context/agent code uses the policy-hash format as the canonical tools shape.
- [ ] `ConversationParticipant` does not resolve/expand/filter tools for execution.
- [ ] `ConversationParticipant` owns defaults/fallback for tools in `effective_tools`.
- [ ] AI layer filters to `allow` policies only before tool registration/execution.
- [ ] Existing app-level tool declarations used by tasks are represented in policy-hash format (including conversation auto-title generation).
- [ ] UI modal checkboxes continue to work and save `allow` entries.
- [ ] Participant chips still show tool count/tooltip from policy entries.
- [ ] No new/updated methods use `_refs` suffix naming.
- [ ] No ask-policy behavior added.

## Scope
- In scope:
  - Model normalization/validation and policy representation.
  - Controller/view mapping between checkbox refs and policy entries.
  - Context/agent/runtime consumption of policy entries.
  - Tests for shape, validation, and behavior compatibility.
- Out of scope:
  - Ask-policy workflow.
  - New UI for deny entries (deny may be accepted in persisted data/tests only).

## Implementation Plan
1. Model policy shape + compatibility
- File: `app/models/conversation_participant.rb`
- Add policy constants (e.g. `TOOL_POLICIES = %w[allow deny]`).
- Replace current string-array normalization with policy-entry normalization:
  - Input `"memories/list"` -> `{ "ref" => "memories/list", "policy" => "allow" }`.
  - Input hash keeps `ref/policy` after normalization and cleanup.
  - Stable sort by `ref`, then `policy`.
- Validation:
  - `tools` must be array.
  - every entry must be hash-like with valid `ref` and valid `policy`.
  - `ref` must exist in registry.
- Add helpers:
  - `effective_tools` => policy entries (hashes).
  - Convert checkbox-selected names to `allow` policy entries directly in controller params/update flow (no new dedicated helper method).
  - Keep model responsible only for shape/validation/compatibility, not execution-time resolution.

2. Context/runtime consumption
- File: `app/libs/ai/contexts/conversation_context.rb`
- Keep `tools` method returning `participant&.effective_tools` (policy hashes).
- Keep participant lookup and model resolution unchanged.

- File: `app/libs/ai/tasks/base_task.rb`
- Update tool registration path to accept policy-hash input and filter `policy == "allow"` before registering tools.
- Keep execution-time filtering in AI layer (task/agent/context path), not in `ConversationParticipant`.

- File: `app/models/conversation.rb`
- Update `request_auto_title_generation!` task tool declaration from string-array to policy-hash array.

3. Controller + modal wiring
- File: `app/controllers/conversation_participants_controller.rb`
- `edit`: set `@participant.tools = @participant.effective_tools` (policy hashes).
- `update`: transform selected checkbox refs into allow-policy hashes using model helper.
- File: `app/views/conversations/_participant_config_modal_frame.html.erb`
- Checkbox checked state based on `participant.effective_tools` policy entries (`allow` selected refs).

4. Participant chip display
- File: `app/views/conversations/_participant_badges.html.erb`
- Build count/tooltip from `effective_tools` policy entries and display allowed entries.

5. Tests
- Update/add tests:
  - `test/models/conversation_participant_test.rb`
    - normalization from strings -> policy hashes.
    - accepts hash entries with `allow|deny`.
    - rejects invalid policy or unknown ref.
    - `effective_tools` behavior with deny overriding allow for execution.
  - `test/controllers/conversation_participants_controller_test.rb`
    - save from checkboxes persists allow-policy hashes.
    - edit preselects checkboxes from `allow` entries in effective policy hashes.
  - `test/libs/ai/contexts/conversation_context_test.rb`
    - `tools` returns policy hashes.
  - `test/libs/ai/tasks/base_task_test.rb` (or nearest task tests)
    - only `allow` policy entries are passed to tool registration/execution path.
  - `test/libs/ai_test.rb` and/or `test/libs/ai/ai_test.rb`
    - update expectations for app-level tool declaration payloads that currently assert string-array tools.

## Verification Commands
1. `bin/rails test test/models/conversation_participant_test.rb`
2. `bin/rails test test/controllers/conversation_participants_controller_test.rb`
3. `bin/rails test test/libs/ai/contexts/conversation_context_test.rb test/libs/ai/agents/advisor_agent_test.rb test/libs/ai/runtimes/conversation_runtime_test.rb`

## Risks and Mitigations
- Risk: older rows stored as string arrays break strict hash validation.
- Mitigation: normalization supports both old and new shapes before validation.

- Risk: UI checked state mismatch after shape migration.
- Mitigation: derive checkbox state from `effective_tools` policy entries only.

## Doc Impact
- likely `none` (internal representation change only), unless we decide to document policy shape under feature data model.
