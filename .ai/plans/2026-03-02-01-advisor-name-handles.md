# Plan: Normalize advisor names as canonical mention handles

## Goal
Use `advisors.name` as the canonical mention handle with strict rules:
- lowercase only
- allowed characters: letters, numbers, dashes (`[a-z0-9-]`)
- strict dash-only immediately (no underscore aliasing)
- backfill/normalize existing data
- fail migration on collisions

## Non-goals
- No new `advisors.handle` DB column.
- No dual identifier model (display name separate from handle) in this change.
- No temporary underscore compatibility layer.

## Scope + assumptions
- Scope: advisor validation/canonicalization, mention parsing and invite lookup behavior, DB data migration/constraints, and related tests.
- Uniqueness scope is per space (case-insensitive): one canonical advisor name per `space_id`.
- Since `name` is the handle, handle mutability is equivalent to name mutability; canonicalization must run on name updates.

## Evidence (key findings)
- `advisors` already has a non-unique index on `[:space_id, :name]`: `db/schema.rb` (`index_advisors_on_space_id_and_name`).
- `Advisor` currently validates `name` presence only (no format/canonicalization/uniqueness constraint): `app/models/advisor.rb`.
- Mention extraction currently allows underscores and dashes via regex: `Message#mentions` in `app/models/message.rb`.
- Mention matching in conversation flow is fuzzy (normalization + partial includes), not deterministic equality: `ConversationLifecycle#parse_mentions` and `#name_matches?` in `app/services/conversation_lifecycle.rb`.
- Invite command currently maps underscore aliases and resolves by lowered `name` account-wide: `app/services/commands/invite_command.rb`.

## Implementation plan (non-code)
1. **Define canonical name contract (name == handle)**
   - Canonicalization rule for persisted `name`: downcase; keep only letters/numbers/dashes; collapse invalid separators into single dashes; trim edge dashes.
   - Enforce format after canonicalization: `\A[a-z0-9]+(?:-[a-z0-9]+)*\z`.
   - Apply canonicalization on create and update of `name`.

2. **Backfill and normalize existing advisor names**
   - Data migration updates existing `advisors.name` to canonical form.
   - Migration fails fast on:
     - canonicalized blank/invalid names
     - canonical collisions within the same `space_id`
   - Failure output should identify conflicting advisor IDs, original names, canonical names, and `space_id`.

3. **Enforce DB-level constraints (no new column)**
   - Replace existing non-unique `[:space_id, :name]` index with case-insensitive uniqueness enforcement per space.
   - Preferred: unique functional index on `[:space_id, lower(name)]` (or DB-equivalent expression-based unique index).
   - Add/keep constraints needed so invalid canonical names cannot be persisted (model validation plus DB check if feasible).

4. **Switch mention and invite behavior to exact canonical name matching**
   - Mentions trigger advisors only by exact `@name` canonical token (plus existing `@all/@everyone`).
   - Remove underscore aliasing immediately (`@data_science` does not map to `@data-science`).
   - Invite lookup resolves advisor by canonical `name` scoped to conversation space.

5. **Update tests for strict behavior**
   - Replace fuzzy/partial/underscore-compat expectations with exact canonical matching.
   - Add migration/data tests for normalization, collision fail-fast, and invalid canonical name handling.
   - Add/adjust model tests for canonicalization on update and case-insensitive uniqueness per space.

## Acceptance criteria
- `advisors.name` is canonicalized and matches `\A[a-z0-9]+(?:-[a-z0-9]+)*\z` for all rows.
- Case-insensitive uniqueness is enforced in DB for `(space_id, name)` via functional unique index (or equivalent).
- Mention resolution in `open` mode triggers only exact canonical `@name` matches (plus `@all/@everyone`).
- `/invite @name` resolves advisors only within the current conversation space.
- Underscore mention aliasing is not supported.
- Backfill migration aborts with clear diagnostics on collisions/invalid canonical results.

## Risks
- **Behavior break risk:** users relying on underscores or partial names will fail immediately.
  - Mitigation: explicit validation/error messaging and updated placeholder/help copy.
- **Migration halt risk:** production collisions after canonicalization can block deploy.
  - Mitigation: preflight collision query before deploy and remediation playbook.
- **DB compatibility risk:** expression unique index syntax depends on adapter/version.
  - Mitigation: choose Rails migration form compatible with current DB and verify schema dump.

## Verification commands
- Preflight canonical collision/invalid check (before migration):
  - `bin/rails runner 'norm = ->(n){ n.to_s.downcase.gsub(/[^a-z0-9-]+/, "-").gsub(/-+/, "-").gsub(/\A-|-\z/, "") }; rows = Advisor.pluck(:id,:space_id,:name); invalid = rows.select{|id,s,n| norm.call(n).blank? || norm.call(n) !~ /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }; collisions = rows.group_by{|id,s,n| [s,norm.call(n)]}.select{|(s,canon),v| canon.present? && v.size>1}; puts "invalid=#{invalid.size}"; puts "collisions=#{collisions.size}"; collisions.each{|k,v| puts({space_id:k[0], canonical:k[1], advisor_ids:v.map(&:first)}.inspect)}'`
- Apply migrations:
  - `bin/rails db:migrate`
- Focused tests:
  - `bin/rails test test/models/advisor_test.rb`
  - `bin/rails test test/services/conversation_lifecycle_test.rb`
  - `bin/rails test test/services/commands/invite_command_test.rb`
  - `bin/rails test test/models/message_test.rb`
- Broader confidence pass:
  - `bin/rails test`

## Blockers / decisions needed
- None based on current decisions.

## Handoff
- Next workflow after approval: `change` (`bug`/`refactor` scoped to advisor-name canonical mention identity).
- `doc impact`: deferred (update advisor/conversation docs after implementation).