# Plan: Message Create Failure Composer Frame

## Goal

Make failed message creation rerender only the composer/form area for Turbo submissions instead of rerendering `conversations/show`, while preserving the existing success path and keeping non-Turbo HTML fallback reasonable.

## Evidence

- `MessagesController#create` currently calls `load_chat_state` and renders `conversations/show` with `422` on save failure.
- The composer form and validation display are inline in `app/views/conversations/_chat.html.erb`.
- The form already uses `turbo:submit-end->conversation#handleSubmitEnd`, so the success path should remain unchanged.

## Scoped changes

1. Extract the composer markup from `app/views/conversations/_chat.html.erb` into a small partial if needed for clean reuse.
2. Wrap the composer area in a dedicated Turbo frame in the chat view.
3. Update `MessagesController#create` failure handling so Turbo requests render only the composer/frame content with `422`.
4. Preserve the current success response behavior.
5. Keep HTML failure fallback on the full page render path.

## Verification

- Run `get_errors` on the changed files only.
- Do not add or modify tests.

## Out of scope

- Any changes to message success flow, message list rendering, or broader chat page layout.
- Any test additions or refactors outside the composer failure path.
