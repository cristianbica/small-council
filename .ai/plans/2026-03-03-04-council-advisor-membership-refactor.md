# Plan: Remove nested council-advisor routes and centralize council membership editing

## Change type
refactor

## Goal
Eliminate all nested `/councils/:council_id/advisors` routes/actions. Keep advisor CRUD only under `/spaces/:space_id/advisors`. Manage council membership through two `CouncilsController` actions:
- `edit_advisors` (checkbox list)
- `update_advisors` (sync adds/removals)

## Scope
- `config/routes.rb`
- `app/controllers/councils_controller.rb`
- `app/controllers/advisors_controller.rb` (remove council-nested behavior)
- `app/views/councils/show.html.erb`
- `app/views/councils/edit_advisors.html.erb` (new)
- `app/views/advisors/new.html.erb`, `app/views/advisors/edit.html.erb` (remove council-specific breadcrumb branching)
- Controller tests affected by removed/added routes/actions
- `.ai/docs/features/councils.md`, `.ai/docs/features/advisors.md`

## Acceptance criteria
1. No nested `/councils/:council_id/advisors` routes remain.
2. Advisor CRUD is accessible via `/spaces/:space_id/advisors/*` only.
3. `CouncilsController#edit_advisors` renders advisors in current space with checkboxes, pre-checked for currently assigned advisors.
4. `CouncilsController#update_advisors` updates council membership by adding/removing join rows in one submit.
5. `councils#show` links to `edit_advisors` for membership management and no longer depends on nested council advisor routes.
6. Authorization remains creator-only for council membership changes.

## Implementation steps
1. Update routes:
   - remove `resources :advisors` nested under `resources :councils`.
   - add council member routes `get :edit_advisors` and `patch :update_advisors`.
2. Councils controller:
   - remove `remove_advisor` action.
   - add `edit_advisors` + `update_advisors` with creator guard.
   - in `edit_advisors`, load available advisors from council space (excluding scribe, matching current advisor listing behavior).
   - in `update_advisors`, sync `advisor_ids` selection to `council.council_advisors`.
3. Advisors controller + advisor views:
   - remove council-specific `params[:council_id]` branches in controller.
   - simplify `new/edit` views to space-only breadcrumbs/flow.
4. Councils views:
   - update show page management links to `edit_advisors_council_path(@council)`.
   - replace per-row council-removal endpoint usage with centralized edit flow entry.
5. Tests:
   - add councils controller tests for `edit_advisors` and `update_advisors` (success + authorization).
   - remove/adjust advisor controller tests tied to `select`/`add_existing` nested council actions.
6. Docs:
   - update feature docs route tables and council/advisor management behavior descriptions.

## Verification
- `bundle exec ruby -Itest test/controllers/councils_controller_test.rb`
- `bundle exec ruby -Itest test/controllers/advisors_controller_test.rb`
- `bundle exec ruby -Itest test/controllers/advisors_controller_comprehensive_test.rb`

## Out of scope
- New UX beyond checkbox membership editor.
- Changes to conversation/advisor AI behavior.
