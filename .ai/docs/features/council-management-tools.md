# Council Management Tools

Status: legacy. The `app/libs/ai/tools/internal/*` council-management tool set has been removed.

Scribe-only AI tools for managing advisors, councils, and advisor assignments within a space. These tools enforce tenant scoping and require the Scribe advisor in context.

## Current State

Advisor/council assignment and management actions are handled by explicit app endpoints and standard service/model flows.

## Access + Scoping

- Access control and tenant scoping are enforced by controllers/models with `Current.account` + `acts_as_tenant`.

## Implementation Notes

- Remaining runtime-available tools are documented in `../patterns/tool-system.md`.

## Tests

- Legacy tool tests were removed with the internal tool layer cleanup.
