# Plan: Form Filler Simplification (Advisor Profile)

Date: 2026-03-07
Status: Proposed
Change type: refactor

## 1. Goal

Simplify the current Form Filler implementation while preserving current advisor-profile behavior:

- advisor profile remains the only supported profile
- generation remains async
- modal remains visible in pending state
- late AI results are ignored when the modal/request is no longer active

## 2. Non-goals

- No behavior expansion to additional profiles in this plan.
- No change to AI prompt/schema semantics for advisor profile.
- No broad UI redesign of advisor form beyond form-filler flow simplification.
- No migration of unrelated generation flows (for example council description) in this change.

## 3. Evidence (Current State)

- `FormFillersController` currently derives and validates multiple request-specific ids/targets (`stream_name`, `panel_target_id`, `result_target_id`, `error_target_id`) and passes profile UI copy fields from registry.
  - `app/controllers/form_fillers_controller.rb`
- Stimulus controller orchestrates manual `fetch` + `Turbo.renderStreamMessage` + modal lifecycle + error UI handling; this is large for the intended role.
  - `app/javascript/controllers/form_filler_controller.js`
- `TurboFormFillerHandler` is profile-aware and duplicates success/error broadcast methods.
  - `app/libs/ai/handlers/turbo_form_filler_handler.rb`
- `ProfileRegistry` stores copy/presentation fields in addition to prompt/schema/attributes.
  - `app/services/form_fillers/profile_registry.rb`
- Form filler views are currently copy-driven from registry fields rather than I18n by profile key.
  - `app/views/form_fillers/_form_panel.html.erb`
  - `app/views/form_fillers/_pending_panel.html.erb`

## 4. Target Simplified Shape

### 4.1 Controller

- Keep `FormFillersController` with `new`/`create`, but reduce profile data to controller-local constant:
  - `prompt`
  - `schema`
  - `attributes`
- Remove profile copy ownership from service/registry.
- Keep validation strict to supported profile list (`advisor_profile` only).

### 4.2 Turbo-first modal loading

- Replace JS-driven `fetch` stream rendering with Turbo-frame-first loading.
- `new` renders modal/panel content via Turbo frame/stream directly from server.
- JS no longer manually requests HTML stream bodies.

### 4.3 Tiny Stimulus controller

- Reduce controller responsibility to:
  - track active request id
  - react in `resultTargetConnected`
  - apply parsed payload to marked form fields
  - ignore stale/late payloads when request is inactive
- Remove manual modal open/close orchestration that Turbo/dialog semantics can handle.

### 4.4 Generic handler

- Make `turbo_form_filler_handler` generic:
  - one broadcast method with `state` (`success` or `error`) and payload/message
  - target only the unique request result target
- Remove profile copy concerns and profile-heavy behavior from handler.

### 4.5 I18n copy by profile key

- Move profile-specific labels/help/pending text into locale keys, e.g.:
  - `form_fillers.profiles.advisor_profile.*`
- Views read copy via `t(...)`, keyed by active profile.

## 5. Phased Migration (Low Risk)

### Phase 1: Introduce simplified data ownership (no UX change)

1. Add controller-local profile mapping constant (prompt/schema/attributes only).
2. Convert controller and handler to use this mapping for allowed attributes.
3. Keep existing views/JS behavior intact for this phase.

Safety:
- Existing modal/UI remains functional while data ownership is simplified.

### Phase 2: Move copy to I18n

1. Add locale entries for advisor profile modal labels/help/pending text.
2. Update `app/views/form_fillers/*.erb` to use translation keys.
3. Remove copy fields from `ProfileRegistry` (or remove registry entirely if obsolete after Phase 1).

Safety:
- Presentation copy source changes only; runtime generation contract unchanged.

### Phase 3: Turbo-frame-first modal delivery

1. Refactor advisor form integration to rely on Turbo frame/stream loading rather than JS fetch rendering.
2. Update `FormFillersController#new` response shape for Turbo frame-first flow.
3. Keep modal pending behavior unchanged.

Safety:
- Retain current route and action signatures during transition to avoid endpoint churn.

### Phase 4: Shrink Stimulus + generic handler finalization

1. Reduce `form_filler_controller.js` to request-id tracking + `resultTargetConnected` apply/ignore logic.
2. Remove now-unused manual modal lifecycle methods and async error DOM handling if no longer needed.
3. Finalize handler to a single stateful broadcast path and request-target-only addressing.

Safety:
- Preserve late-result ignore behavior by explicit request-id check before apply.

### Phase 5: Cleanup

1. Remove obsolete profile registry/service if fully replaced.
2. Remove dead partial locals and ids no longer needed.
3. Verify no remaining references to removed copy fields or old JS methods.

## 6. Exact Impacted Files

Primary refactor targets:

- `app/controllers/form_fillers_controller.rb`
- `app/javascript/controllers/form_filler_controller.js`
- `app/libs/ai/handlers/turbo_form_filler_handler.rb`
- `app/services/form_fillers/profile_registry.rb` (remove or reduce)
- `app/views/form_fillers/_modal.html.erb`
- `app/views/form_fillers/_form_panel.html.erb`
- `app/views/form_fillers/_pending_panel.html.erb`
- `app/views/form_fillers/_result.html.erb`
- `app/views/advisors/_form.html.erb`
- `config/routes.rb` (verify existing `resource :form_filler` remains sufficient)

Expected new/updated locale file:

- `config/locales/form_fillers.en.yml` (or existing locale file where app keeps form filler strings)

## 7. Verification Plan

Lightweight checks for implementation phase:

1. `bin/rails routes | rg form_filler`
2. `bin/rails zeitwerk:check`
3. `bin/rails test test/controllers/form_fillers_controller_test.rb` (if added)
4. `bin/rails test test/system/advisors_test.rb` (or closest advisor form system test)

Manual validation (required):

1. Open advisor new/edit form and launch AI form filler.
2. Submit valid description; modal remains open with pending state.
3. On success, fields (`name`, `short_description`, `system_prompt`) are populated.
4. Close modal before completion; verify late result does not mutate form fields.
5. Trigger invalid request/profile path and confirm user-visible error state remains safe.

Testing note:

- If adding/adjusting automated tests is deferred for speed, record that explicitly in implementation closeout and run at least manual validation above.

## 8. Risks and Mitigations

- Risk: Turbo-frame migration causes modal open/regression.
  - Mitigation: phase migration so old behavior remains until Turbo frame path is verified.
- Risk: late result still applies after modal close.
  - Mitigation: keep strict active-request id guard in Stimulus before applying payload.
- Risk: i18n key mistakes break labels/help copy.
  - Mitigation: use deterministic key namespace and verify rendered modal text in manual pass.
- Risk: removing profile registry too early breaks allowed attributes validation.
  - Mitigation: first move prompt/schema/attributes into controller-local constant, then remove registry usage.

## 9. Rollback Strategy

- Roll back by phase rather than one large cutover:
  - If Phase 3 fails, revert advisor form and `new` response shape to prior modal loading while keeping Phase 1-2 simplifications.
  - If Phase 4 fails, keep previous Stimulus methods temporarily and only ship controller/i18n simplification.
- Keep commits split by phase so each simplification can be reverted independently.
- Preserve route contract (`new`/`create`) during migration to reduce rollback surface.

## 10. Assumptions and Decisions Requiring Approval

1. Keep `advisor_profile` as the only supported profile in this simplification.
2. Consolidate profile mapping into `FormFillersController` (removing or minimizing `ProfileRegistry`).
3. Introduce/standardize locale keys for all profile-specific form filler copy.
4. Prefer Turbo-frame-first modal loading and reduce Stimulus to result application logic.
5. Keep existing `resource :form_filler` route unless implementation reveals a hard blocker.

## 11. Doc and Memory Impact

- `doc impact`: updated (this plan artifact only)
- `memory impact`: none

Approve this plan?
