## Approved Plan

- Keep scope limited to the message interactions UI/render path and `ModelInteraction` broadcasts.
- Make `app/views/messages/interactions.html.erb` the main entry view that subscribes to a message-specific Turbo stream and renders a single loaded-content partial.
- Collapse the active render path to `interactions.html.erb -> _interactions_content.html.erb -> _interaction_item.html.erb`.
- Update `ModelInteraction` to broadcast directly to the message interactions view in append mode and stop broadcasting any count target.
- Remove the unused count/frame/list partials from the active path when safe.