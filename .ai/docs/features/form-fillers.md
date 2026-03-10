# Form Fillers

Reusable AI-assisted form filling for resource creation and editing.

## Overview

- `FormFillersController` provides one transient flow for AI-generated form content.
- The current supported profiles are:
  - `advisor_profile`
  - `council_profile`
- The flow is asynchronous:
  1. open a Turbo-rendered modal
  2. submit a short description
  3. queue `AI.generate_text(..., async: true)`
  4. keep the modal in a pending state
  5. apply the structured result back into marked form fields when the job finishes

## Current entrypoints

- Advisor form uses `profile=advisor_profile` and fills:
  - `name`
  - `short_description`
  - `system_prompt`
- Council form uses `profile=council_profile` and fills:
  - `name`
  - `description`

The feature is mounted as a singular resource:

```text
/form_filler/new?profile=advisor_profile
/form_filler/new?profile=council_profile
/form_filler
```

## Request flow

1. A resource form wraps itself in `data-controller="form-filler"`.
2. The form declares fillable fields with `data-form-filler-target="fillable"` and `data-form-filler-attribute="..."`.
3. Clicking `Generate with AI` loads `FormFillersController#new` into a Turbo frame.
4. `new` validates `profile`, creates a fresh `filler_id`, and renders the modal without layout.
5. Submitting the modal posts to `FormFillersController#create` with `profile`, `filler_id`, and `description`.
6. `create` queues `AI.generate_text(...)` with:
   - the profile prompt
   - the profile schema
   - `space: Current.space`
   - `handler: { type: :turbo_form_filler, filler_id: ... }`
   - `async: true`
7. The controller swaps the modal body into a pending state and subscribes to `form_filler_result_<filler_id>`.
8. `AI::Handlers::TurboFormFillerHandler` broadcasts either:
   - `success` with JSON payload
   - `error` with a user-facing message
9. `form_filler_controller.js` receives the hidden result target, parses the payload, applies matching keys to the marked inputs, dispatches `input` and `change`, and closes the modal.

## Server responsibilities

### `FormFillersController`

- Keeps the profile registry in `PROFILES`.
- Validates supported profiles and presence of `filler_id`.
- Validates non-blank descriptions.
- Starts the async generation run.
- Renders three UI states:
  - form
  - pending
  - error

### `AI.generate_text`

- Provides the high-level utility runtime entrypoint.
- Builds a `TextTask` with prompt, schema, and description.
- Builds a `SpaceContext` from `Current.space`.
- Delegates to `AI::Runner`.

### `TurboFormFillerHandler`

- Receives the completed `AI::Result`.
- Uses Turbo stream broadcast replace on `form_filler_result_<filler_id>`.
- Serializes `result.response.content` for success.
- Broadcasts an error state for failed runs or handler-side exceptions.

## Frontend contract

### Form integration

Each supported form needs:

- a wrapper with `data-controller="form-filler"`
- a trigger link targeting a dedicated Turbo frame
- one `turbo-frame` placeholder for the modal
- one or more fillable fields tagged with `data-form-filler-attribute`

### Stimulus behavior

`form_filler_controller.js` is intentionally small:

- `modalTargetConnected` opens the dialog
- `handleDialogClose` removes the modal from the DOM
- `resultTargetConnected` handles success or error state
- `applyPayload` only fills attributes explicitly declared on the form

## Localization

Profile-specific modal and pending copy lives in `config/locales/en.yml` under:

- `form_fillers.profiles.advisor_profile.*`
- `form_fillers.profiles.council_profile.*`
- shared errors under `form_fillers.errors.*`

## Relationship to the AI runtime

- This feature uses the new utility runtime, not the legacy advisor/council generation endpoints.
- `AdvisorsController#generate_prompt` has been removed from the current flow.
- `CouncilsController#generate_description` has been removed from the current flow.
- The form-filler flow is the current reusable async utility generation surface in the app.

## Key files

- `app/controllers/form_fillers_controller.rb`
- `app/javascript/controllers/form_filler_controller.js`
- `app/libs/ai/handlers/turbo_form_filler_handler.rb`
- `app/views/form_fillers/new.html.erb`
- `app/views/form_fillers/_form.html.erb`
- `app/views/form_fillers/_pending.html.erb`
- `app/views/form_fillers/_result.html.erb`
- `app/views/advisors/_form.html.erb`
- `app/views/councils/_form.html.erb`

## Implementation notes

- The feature is currently profile-driven but intentionally narrow; adding a new profile means extending the `PROFILES` map and adding prompt/schema/copy support.
- Result application is key-based, so the schema output keys must stay aligned with the form field attributes.
- The modal remains open during background execution; the result is applied only after the async broadcast arrives.
