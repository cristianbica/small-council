# Turbo Streams

Real-time UI updates via Action Cable and Turbo.

## Setup

### 1. Subscribe in view

```erb
<%= turbo_stream_from "conversation_#{@conversation.id}" %>

<div id="messages">
  <%= render @messages %>
</div>
```

### 2. Wrap content in turbo_frame_tag

```erb
<%= turbo_frame_tag "message_#{message.id}" do %>
  <div class="message">
    <%= message.content %>
  </div>
<% end %>
```

### 3. Broadcast from jobs/controllers

```ruby
Turbo::StreamsChannel.broadcast_replace_to(
  "conversation_#{conversation.id}",
  target: "message_#{message.id}",
  partial: "messages/message",
  locals: { message: message }
)
```

## Broadcast Operations

- `broadcast_append_to` - Add to end of container
- `broadcast_prepend_to` - Add to start of container
- `broadcast_replace_to` - Replace existing element
- `broadcast_remove_to` - Remove element
- `broadcast_update_to` - Update content (without replacing element)

## Multi-tenancy Considerations

Always include tenant-scoped identifiers in stream names:

```ruby
# Good - includes account-specific conversation ID
"conversation_#{conversation.id}"

# Bad - could leak across accounts
"conversation_#{conversation.public_uid}"
```

## Testing

Turbo Streams work in integration tests (full stack) but not in controller tests (no JS).

To verify broadcasts in tests, use `assert_turbo_stream` or check side effects:

```ruby
test "job broadcasts update" do
  expect_turbo_stream_broadcast(conversation, count: 1) do
    GenerateAdvisorResponseJob.perform_now(message_id: message.id)
  end
end
```

## Common Patterns

### Pending State

Show placeholder that gets replaced:

```erb
<%= turbo_frame_tag "message_#{placeholder.id}" do %>
  <div class="animate-pulse">Thinking...</div>
<% end %>
```

Job broadcasts replacement with actual content.

### Error State

Update with error styling:

```ruby
def handle_error(message, error)
  message.update!(status: "error", content: "[Error: #{error}]")
  
  Turbo::StreamsChannel.broadcast_replace_to(
    "conversation_#{message.conversation.id}",
    target: "message_#{message.id}",
    partial: "messages/message",
    locals: { message: message }
  )
end
```

## Performance

- Use `includes(:sender)` when rendering lists
- Consider pagination for long conversations
- Broadcasts are async; job queue health matters

## Debugging

Check browser console for WebSocket connections:
- Look for `/cable` endpoint
- Monitor subscription confirmations
- Check for authorization errors
