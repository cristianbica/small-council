# Plan: Model interactions modal + live streaming refactor

## Change type
feature

## Goal
Implement a single cohesive refactor around model interactions:
1. Resize interactions modal to ~80% viewport width and ~95% viewport height.
2. Load interactions modal content asynchronously so large conversations load faster.
3. Stream model interactions live while the modal is open.
4. In chat, replace advisor pending text (`[advisor] is thinking...`) with `...`.
5. Show the interactions button immediately when an advisor starts working (before first interaction record exists).
6. For system→model interactions, render three sections in the modal: `Request`, `Request Tools`, `Response`.
7. In chat view, increase the chat content area width beyond the current 768px constraint.
8. In chat view, reduce chat message font size slightly for denser readability.

## Scope
- `config/routes.rb`
- `app/controllers/messages_controller.rb`
- `app/models/model_interaction.rb`
- `app/views/messages/_message.html.erb`
- `app/views/conversations/show.html.erb` (or the chat container partial defining max width)
- `app/views/messages/_interactions_content.html.erb` (new)
- `app/views/messages/_interactions_list.html.erb` (new)
- `app/views/messages/_interaction_item.html.erb` (new)
- `test/controllers/messages_controller_test.rb`
- `.ai/docs/features/*` docs if behavior references need updating

## Acceptance criteria
1. Interactions modal opens at roughly 80% viewport width and 95% viewport height.
2. Conversation initial render does not include full interaction payloads for every advisor message.
3. Interactions modal content is fetched asynchronously and updates live when new model interactions are created.
4. While advisor message is pending, chat bubble shows `...` (display-only) instead of `[Advisor] is thinking...`.
5. Interactions button is visible for advisor-owned pending messages immediately.
6. For chat/system→model interaction records, modal displays:
   - Request (without tools)
   - Request Tools
   - Response
7. Tool interaction records continue to render correctly.
8. Chat area max width is increased from the current constraint so more conversation content fits horizontally.
9. Chat message font size is slightly reduced while keeping readability.

## Implementation steps
1. Add nested message member route for interaction modal content endpoint.
2. Add `MessagesController#interactions`:
   - scope to current conversation/space
   - render interactions modal content partial for one message.
3. Refactor message modal in `messages/_message`:
   - keep lightweight dialog shell
   - lazy-load content into a `turbo-frame` when opening modal
   - resize modal to ~80vw and ~95vh.
4. Add Turbo stream broadcasting from `ModelInteraction` on create:
   - broadcast replace/append for message-specific interactions list target.
5. Build interaction partials:
   - shared list partial
   - item partial with conditional rendering:
     - chat interactions: split `Request` and `Request Tools`
     - tool interactions: keep request/response format.
6. Update pending advisor display logic in `messages/_message` to show `...`.
7. Show interactions button when sender is advisor and message is pending (even if interaction count is 0).
8. Add/adjust controller test(s) for `MessagesController#interactions` authorization and response.
9. Update chat layout styles to increase chat area width (remove/raise 768px-style constraint).
10. Reduce chat message font size slightly in message rendering styles/classes.
11. Update docs if needed for interactions modal/chat behavior.

## Verification
- `bundle exec ruby -Itest test/controllers/messages_controller_test.rb`
- `bundle exec ruby -Itest test/controllers/conversations_controller_test.rb` (if impacted)
- run any targeted tests that fail due to partial refactor

## Out of scope
- Changing interaction recording schema in DB migrations.
- Fully real-time token streaming before any interaction callbacks fire.
