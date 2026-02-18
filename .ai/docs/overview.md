# App overview

## What this app does

This app is a multi-tenant business application that manages core operational workflows (for example: members/customers, billing/payments, and admin configuration).

It is used by staff to run day-to-day operations, and by administrators to configure company-level settings and report on activity.

## Tech stack

- Backend: Rails 8.1.2
- Database: PostgreSQL
- Frontend: Hotwire/Turbo (planned)
- Background jobs: Solid Queue
- Tests: Minitest
- Authentication: authentication-zero (47 tests passing)
- Multi-tenancy: acts_as_tenant (ready, not yet enabled)

## Repo landmarks

- Primary app code: `app/`
- Tests: `test/`
- CI config: `.github/workflows/`

Rules:
- Keep this file to a few paragraphs + bullet lists.
- Prefer concrete commands/paths over vague descriptions.
