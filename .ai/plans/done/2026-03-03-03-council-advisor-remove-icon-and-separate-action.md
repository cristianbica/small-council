# Plan: Council advisor removal via council-specific action and hover trash icon

## Change type
bug

## Goal
On `councils#show`, remove the current 3-button advisor actions and replace with a hover-visible trash icon on the right that removes an advisor from the council only. Keep `advisors#destroy` behavior unchanged (advisor deletion at advisor scope).

## Scope
- `app/views/councils/show.html.erb`
- `config/routes.rb`
- `app/controllers/councils_controller.rb`
- Controller tests for council-specific removal path

## Acceptance criteria
1. `advisors#destroy` is restored/left as direct advisor deletion behavior.
2. A new council-specific controller action handles removing advisor membership from a council (join-record removal only).
3. `councils#show` no longer shows the current 3-button advisor actions block.
4. `councils#show` shows a trash icon on the right for each advisor row, only visible on row hover, creator-only.
5. Clicking trash removes advisor from the council and redirects back to council show with success/error flash.

## Implementation steps
1. Add member route under councils for council-specific unassign action (no reuse of `advisors#destroy`).
2. Implement `CouncilsController#remove_advisor` with creator guard + scoped lookup + join-record delete.
3. Revert `AdvisorsController#destroy` to advisor deletion behavior only.
4. Update advisor rows in `councils/show`:
   - remove existing edit/remove buttons block,
   - keep row clickable behavior,
   - add hover-revealed right-aligned trash icon button for creator.
5. Add/adjust controller tests for `remove_advisor` behavior and authorization.

## Verification
- Run targeted controller tests for councils and advisors.
- Run any council/advisor system/controller tests directly impacted by this change.

## Out of scope
- Any redesign beyond the hover trash icon behavior.
- Changes to advisor edit/create flows.
- Changes to AI tool-based advisor/council assignment APIs.
