# Council Management Tools

Scribe-only AI tools for managing advisors, councils, and advisor assignments within a space. These tools enforce tenant scoping and require the Scribe advisor in context.

## Tool Coverage

### Advisors
- `create_advisor`
- `list_advisors`
- `get_advisor`
- `update_advisor`

### Councils
- `create_council`
- `list_councils`
- `get_council`
- `update_council`

### Assignments
- `assign_advisor_to_council`
- `unassign_advisor_from_council`

## Access + Scoping

- **Scribe-only**: tools return `Scribe access required` when invoked by non-scribe advisors.
- **Tenant-safe**: tools scope all data through the provided `space` context (account-scoped via `acts_as_tenant`).
- **Input validation**: tool arguments are validated for required fields and account ownership (LLM model ownership, advisor/council presence in space).

## Implementation Notes

- Tools live under `app/libs/ai/tools/internal/` and follow `AI::Tools::BaseTool` patterns.
- Registration in `AI::ContentGenerator#advisor_tools` adds these tools only for the Scribe.
- Councils automatically ensure the Scribe advisor is assigned after creation.

## Tests

- Unit tests for each tool under `test/ai/unit/tools/internal/`.
- Integration test for assign/unassign flow under `test/ai/integration/assign_unassign_advisor_flow_test.rb`.
