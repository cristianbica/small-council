# Plan: Implement tools to manager council and advisors

Date: 2026-03-01

## Goal
- Provide Scribe tools to create, list, get details, and update advisors and councils.
- Provide tools to assign and unassign advisors to councils.

## Non-goals
- Full redesign of council/advisor admin UI.
- Deleting councils/advisors.
- Automatic creation without explicit user request.

## Scope + assumptions
- Scope limited to tool definitions, permissions, and orchestration flow.
- Tool execution is mediated through existing AI::Tools infrastructure.
- Tools are available only to Scribe.
- Tenant scoping enforced via acts_as_tenant.
- Advisor tools do not accept `llm_model` in create/update inputs (existing records remain unchanged).

## Tools

### Advisors
1. `create_advisor`
2. `list_advisors`
3. `get_advisor`
4. `update_advisor`

### Councils
5. `create_council`
6. `list_councils`
7. `get_council`
8. `update_council`

### Assignments
9. `assign_advisor_to_council`
10. `unassign_advisor_from_council`

## Steps
1. Define tool schemas (inputs/outputs) for all 10 tools.
2. Implement tool classes in `app/libs/ai/tools/` using existing context (space/account).
3. Enforce authorization: Scribe-only.
4. Validate inputs and ensure IDs are within current account.
5. Implement assignment logic via `CouncilAdvisor` join records.
6. Add unit tests per tool + integration tests for assign/unassign flow.
7. Validate flow in a dev conversation with Scribe.

## Verification
- Run tool-related tests and any new service tests.
- Manually verify Scribe can list/create/update and assign/unassign.

## Doc impact
- Add: `.ai/docs/features/council-management-tools.md`

## Rollback (if applicable)
- Disable or remove tool registrations and revert handlers.
