# Feature Plan: Reusable Form Filler Flow, Advisor Profile First

Date: 2026-03-07
Status: Proposed
Change type: feature

## 1. Goal

- Add a reusable form-filler flow for HTML forms that opens a Turbo-rendered modal, collects a generation description, runs AI generation asynchronously, and fills marked form fields when structured output arrives.
- Ship v1 only for `advisor_profile` on the advisor form.
- Keep the backend and Stimulus contracts reusable so later profiles can be added without inventing a second flow.

## 2. Non-goals

- No implementation in this workflow.
- No support in v1 for council, conversation, or arbitrary custom schemas.
- No new persisted database model unless implementation uncovers a hard requirement.
- No attempt to preserve or expand the current `content-generator` / `prompt-generator` UI patterns beyond what is needed to replace them for the advisor-profile path.

## 3. Recommendation

### 3.1 Controller and resource naming

- Recommend `FormFillersController`.
- Recommend a singular route: `resource :form_filler, only: [:new, :create]`.
- Recommended helpers:
  - `new_form_filler_path(profile: :advisor_profile, request_id: ...)`
  - `form_filler_path`
- This keeps naming aligned with the reusable `form-filler` Stimulus controller and avoids the overly broad `content` label.

Why this naming fits:

- The server resource is a transient form-filling request, not the final advisor record.
- `new` cleanly maps to “render the modal via Turbo Stream”.
- `create` cleanly maps to “submit description/profile and enqueue generation”.
- A singular resource avoids implying users can list or browse generation requests.

### 3.2 Front-end contract

- Keep the reusable Stimulus controller name as `form-filler`.
- v1 form contract:
  - form root: `data-controller="form-filler"`
  - modal URL: `data-form-filler-url-value="new_form_filler_path(profile: :advisor_profile)"`
  - fields to populate are declared per input, for example: `data-form-filler-target="fillable"` plus `data-form-filler-attribute="short_description"`
- The button should call the controller, not encode flow logic inline.
- The URL is the source of truth for the profile; the controller should not require a separate form-level profile value.

## 4. Evidence Snapshot

- Existing advisor generation UI is in `content-generator` on the advisor form and uses an inline `<dialog>` plus JSON fetch in [app/views/advisors/_form.html.erb](app/views/advisors/_form.html.erb) and [app/javascript/controllers/content_generator_controller.js](app/javascript/controllers/content_generator_controller.js).
- Existing council generation UI uses the same controller but a different synchronous JSON backend path in [app/views/councils/_form.html.erb](app/views/councils/_form.html.erb) and [app/controllers/councils_controller.rb](app/controllers/councils_controller.rb).
- The current advisor async path already calls `AI.generate_text(... async: true)` with prompt `tasks/advisor_profile` and schema `advisor_profile` in [app/controllers/advisors_controller.rb](app/controllers/advisors_controller.rb), and those assets exist in [app/libs/ai/prompts/tasks/advisor_profile.erb](app/libs/ai/prompts/tasks/advisor_profile.erb) and [app/libs/ai/schemas/advisor_profile_schema.rb](app/libs/ai/schemas/advisor_profile_schema.rb).
- The current advisor async path references `handler: { type: :turbo_advisor_profile }`, but no corresponding handler file exists under `app/libs/ai/handlers/`; only [app/libs/ai/handlers/base_handler.rb](app/libs/ai/handlers/base_handler.rb) exists. This means the closest existing async utility path is incomplete and should not be treated as a finished reusable pattern.
- Async AI execution already has a stable runtime entrypoint through [app/libs/ai.rb](app/libs/ai.rb), [app/libs/ai/runner.rb](app/libs/ai/runner.rb), and [app/jobs/ai_runner_job.rb](app/jobs/ai_runner_job.rb).
- Real-time Turbo broadcasts already exist for conversation updates in [app/jobs/generate_advisor_response_job.rb](app/jobs/generate_advisor_response_job.rb) and [app/models/model_interaction.rb](app/models/model_interaction.rb), so the app already uses Turbo Streams for async UI updates.
- The app does not currently show a reusable Turbo-streamed modal container pattern. Existing modals are either inline `<dialog>` elements or message-specific dialogs in [app/views/messages/_message.html.erb](app/views/messages/_message.html.erb).
- Existing route conventions favor REST-ish member/collection actions; the current generation endpoints are fragmented across `generate_prompt` and `generate_description` in [config/routes.rb](config/routes.rb).

## 5. Scope and Assumptions

### 5.1 In scope for v1

- Advisor create/edit form only.
- One supported profile: `advisor_profile`.
- One modal textarea for the user description plus helper copy tied to the profile.
- Async generation using the existing AI runtime.
- Turbo Stream delivery of modal state and generation result.
- Stimulus-based mapping from returned JSON fields into marked form inputs.

### 5.2 Explicit assumptions

- Use `AI.generate_text` / `AI::Runner` for generation instead of routing v1 through `AI::ContentGenerator`.
- The generation result can remain ephemeral and does not need database persistence.
- Current authenticated app context plus `Current.space` is sufficient for model selection and authorization in this flow.
- “If modal closes before completion, nothing happens” means the late result must not mutate the form after the modal/request instance is no longer active.

## 6. Proposed Design

### 6.1 Request lifecycle

1. The advisor form includes a small reusable `form-filler` wrapper and a stable container for Turbo Stream inserts.
2. Clicking the trigger asks `FormFillersController#new` for a modal via the configured URL, adding a client-generated `request_id`.
3. `new` validates the profile and returns a Turbo Stream that renders a shared modal partial into the form-specific container.
4. The modal includes:
   - helper copy for `advisor_profile`
   - a textarea for the generation description
   - hidden fields or data attributes carrying `profile` and `request_id`
  - a submit button targeting `FormFillersController#create`
5. `create` validates `profile` and `description`, resolves the prompt/schema pair from a server-side registry, and queues `AI.generate_text(... async: true, handler: ...)`.
6. `create` responds immediately with a Turbo Stream that keeps the modal open and swaps it into a loading state.
7. When the async run completes, a dedicated handler broadcasts a Turbo Stream payload for that `request_id`.
8. The broadcast updates a hidden result target in the same form wrapper with structured JSON plus the `request_id`.
9. The `form-filler` Stimulus controller observes the result target, verifies the `request_id` is still active, parses the JSON, and fills matching `[data-form-filler-attribute]` inputs.
10. After applying the result, the controller closes and clears the modal/result state.

### 6.2 Reusable abstraction boundaries

- Server-side profile registry:
  - map `profile` to prompt, schema, helper text, button label, and allowed output attributes
  - v1 contains only `advisor_profile`
- Shared controller/resource:
  - one `new` action for modal rendering
  - one `create` action for queueing generation
- Shared Turbo modal partial:
  - receives profile metadata from the registry
  - stays generic except for copy and labels
- Shared Stimulus controller:
  - opens the modal
  - tracks `request_id`
  - applies JSON output into `fillable` targets by matching `data-form-filler-attribute`
  - ignores stale or inactive results

This keeps v1 advisor-only while making later additions a registry entry plus profile-specific copy/schema, not a second architecture.

### 6.3 Delivery mechanism details

- Use a client-generated `request_id` per fill attempt.
- Broadcast results to a target namespaced by `request_id`, not by advisor id or user id.
- Keep the Turbo subscription/result target inside the modal or form-filler container created for that request.
- On modal close, remove or invalidate the active request target so late broadcasts no-op on the client.
- Return structured JSON, not field-by-field HTML fragments. The server should remain responsible for schema validation; the client should remain responsible for mapping schema keys onto existing inputs.

## 7. Implementation Phases

### Phase 1: Normalize the surface area

1. Add the singular `form_filler` route and `FormFillersController` plan target.
2. Define a server-side profile registry with only `advisor_profile`.
3. De-scope the old advisor `generate_prompt` endpoint from the new flow rather than trying to keep both active for the same UI.

### Phase 2: Introduce the reusable modal flow

1. Add a reusable Turbo Stream insertion point on the advisor form.
2. Add `FormFillersController#new` to render the modal via Turbo Stream.
3. Add a shared modal partial with profile helper text, textarea, submit state, and loading state.

### Phase 3: Wire async generation and result publishing

1. Add `FormFillersController#create` to validate params and enqueue generation.
2. Add a concrete AI handler for utility generation completion that broadcasts to the per-request target.
3. Keep the modal open during job execution and switch it into a loading/pending state through Turbo Stream.
4. Stream either success JSON payload or an error state back into the same modal/form-filler container.

### Phase 4: Add the reusable Stimulus controller

1. Add `form_filler_controller.js`.
2. Support:
   - trigger click -> request modal
   - active `request_id` tracking
   - result target observation/parsing
   - field lookup by `data-form-filler-attribute`
   - stale result ignore on close or replacement request
3. Apply it only to the advisor form in v1.

### Phase 5: Remove duplication and align the advisor UI

1. Replace the advisor form’s current `content-generator` usage with `form-filler`.
2. Remove advisor-specific inline modal markup from the form once the shared modal exists.
3. Leave council generation out of scope, but note it as the first follow-on consumer if v1 lands cleanly.

## 8. Impacted Areas

- Routing: [config/routes.rb](config/routes.rb)
- New controller: `app/controllers/form_fillers_controller.rb`
- Advisor form integration: [app/views/advisors/_form.html.erb](app/views/advisors/_form.html.erb)
- Shared modal/result partials: likely `app/views/form_fillers/` and/or `app/views/shared/`
- Stimulus: `app/javascript/controllers/form_filler_controller.js`
- AI runtime handler: `app/libs/ai/handlers/`
- Optional cleanup/deprecation touchpoint: [app/controllers/advisors_controller.rb](app/controllers/advisors_controller.rb)

## 9. Tests and Verification

Initial implementation pass:

- Tests are deferred per user direction.
- Verification should still include the exact manual or command-based checks run during implementation.

### 9.1 Controller/request tests

- Add tests for `FormFillersController#new`:
  - valid `advisor_profile` returns Turbo Stream modal content
  - invalid/unsupported profile returns `422`
- Add tests for `FormFillersController#create`:
  - missing description returns `422`
  - unsupported profile returns `422`
  - valid request enqueues async generation and returns Turbo Stream loading state

### 9.2 AI handler tests

- Add focused unit tests for the utility Turbo handler:
  - success result broadcasts the expected target and serialized JSON
  - failure result broadcasts an error state instead of malformed content

### 9.3 Stimulus/system coverage

- Add a system test for advisor form fill:
  - click trigger
  - modal renders
  - submit description
  - loading state appears and modal stays open
  - async result fills `name`, `short_description`, and `system_prompt`
- Add a system or JS-level test for the close-before-complete path:
  - close modal before broadcast
  - later result does not mutate the form

### 9.4 Commands to run during implementation

- `bin/rails test test/controllers/form_fillers_controller_test.rb`
- `bin/rails test test/ai test/controllers/advisors_controller_comprehensive_test.rb`
- `bin/rails test` if the targeted suite passes and the change touches shared runtime pieces

## 10. Risks and Mitigations

- Risk: duplicate architecture if the old `content-generator` flow remains half-active.
  - Mitigation: make advisor form v1 use only the new flow.
- Risk: late async results can mutate a form after the user closes the modal.
  - Mitigation: require active `request_id` matching before applying results, and remove or invalidate the per-request target on close.
- Risk: a generic controller becomes an untyped catch-all.
  - Mitigation: keep a strict profile registry and reject unknown profiles.
- Risk: missing or weak Turbo target scoping causes cross-form updates.
  - Mitigation: namespace all modal/result targets by `request_id` and keep them inside the form-filler root.
- Risk: v1 overreaches into council/conversation support.
  - Mitigation: keep the registry to one profile and document later expansion as follow-on work only.
- Risk: the current async advisor path is already incomplete because its handler is missing.
  - Mitigation: build the new handler explicitly for the `content_generation` flow instead of relying on the unfinished controller path.

## 11. Doc Impact

- `doc impact`: updated
- Update feature or pattern docs after implementation to describe the reusable form-filler flow, the `form_filler` route contract, and how new profiles are registered.
- No doc change is needed in this planning step beyond this plan artifact.

## 12. Open Items Kept as Assumptions

- Assume top-level singular routing is acceptable even though advisor create/edit is space-nested.
- Assume Turbo Stream response plus existing app cable infrastructure is the preferred delivery path over polling.
- Assume no progress streaming is required for v1 beyond a pending/loading state.

## 13. Approval Gate

Recommended next step after approval:

1. Implement `FormFillersController` + route + shared profile registry.
2. Wire `form-filler` into the advisor form only.
3. Add the async Turbo handler and advisor-focused tests.

Approve this plan?
