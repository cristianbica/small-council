# Plan: Single-Page Provider Add Flow (Turbo + Test Before Save)

## Change type
refactor

## Goal
Replace the multi-step provider wizard with a single-page provider creation flow where:
1) user selects provider type,
2) Turbo updates the provider-specific form,
3) user tests connection,
4) Save button is available only after successful test,
5) API keys are never exposed in URL query strings.

## Scope
- In scope:
  - Remove wizard routes/actions/views and switch entry points to Providers#new.
  - Implement provider-type picker on new page using Turbo Frame GET requests.
  - Add provider-specific form partial rendered inside frame.
  - Add client-side controller for test-connection action and save-button gating.
  - Keep final create as POST body only; no credentials in URL.
  - Keep ProvidersController#create as persistence-only (normal validations + save), with no connection-test call in create.
  - Replace wizard integration tests with single-page flow tests.
  - Update provider feature docs to reflect the new flow.
- Out of scope:
  - Provider edit page behavior.
  - AI model management pages.
  - Existing unrelated unstaged files.

## Implementation
1. Routes + controller
- Remove wizard-related routes: wizard, wizard_step, wizard_back, wizard_cancel.
- Keep collection route: test_connection.
- ProvidersController#new:
  - accept optional provider_type param;
  - when turbo-frame request, render only provider form partial.
- ProvidersController#create:
  - build provider from strong params;
  - persist provider using existing model validations only;
  - do not call test-connection here;
  - redirect index on success, render new on validation failure.

2. Views
- Update providers index/button/empty state to point to new_provider_path.
- Rewrite providers new page:
  - provider type cards/buttons as link_to new_provider_path(provider_type: ...), target frame.
  - turbo_frame_tag provider form area.
- Add partial for provider form fields per provider type:
  - OpenAI shows organization_id;
  - OpenRouter hides organization_id.
  - includes Test Connection button and Save button initially disabled/hidden.
- Delete wizard templates.

3. JS controller
- Add Stimulus controller (e.g., provider_form_controller.js):
  - reads current form values;
  - POST JSON to /providers/test_connection with CSRF;
  - on success: show success message, enable Save button;
  - on failure: show error message, keep Save disabled;
  - reset save-state when relevant inputs change.

4. Tests
- Remove wizard integration test file and add/update integration test for new page Turbo behavior.
- Add assertions:
  - selecting provider type returns correct frame content,
  - test_connection endpoint works,
  - create does not invoke ProviderConnectionTester,
  - create succeeds when test succeeds,
  - no redirects include api_key query param.

5. Docs
- Update .ai/docs/features/providers.md to describe single-page Turbo flow and no credential URL exposure.

## Verification
- bin/rails test test/controllers/providers_controller_test.rb
- bin/rails test test/integration/providers_single_page_test.rb

## Risks and mitigations
- Risk: client-only test gating can be bypassed.
- Mitigation: keep Save button disabled until successful test in UI; treat this as UX contract rather than hard server gate.
- Risk: Turbo frame partial rendering may lose validation context.
- Mitigation: render full new page on create errors and preserve selected provider_type.
