# Background Jobs

Async job processing using Solid Queue.

## Configuration

Solid Queue is configured in `config/recurring.yml` and uses database tables for job storage.

## Job Structure

Canonical runtime async execution uses `AIRunnerJob`:

```ruby
class AIRunnerJob < ApplicationJob
  queue_as :default

  def perform(task:, context:, handler: nil, tracker: nil)
    AI::Runner.new(task: task, context: context, handler: handler, tracker: tracker).run
  end
end
```

Advisor response generation and retry both enqueue `AIRunnerJob` via `AI.generate_advisor_response(..., async: true)`.

## Multi-tenancy in Jobs

**Critical**: Always set tenant context explicitly in jobs:

```ruby
ActsAsTenant.current_tenant = account
# ... do work ...
ensure
  ActsAsTenant.current_tenant = nil
end
```

Without this, queries won't be scoped to the correct account.

## Idempotency

Design jobs to be safely retryable:

```ruby
def perform(message_id:)
  message = Message.find_by(id: message_id)
  return unless message          # Skip if deleted
  return unless message.pending? # Skip if already processed

  # Do work...
end
```

## Enqueuing

From conversation runtime classes:

```ruby
AI.generate_advisor_response(
  advisor: message.sender,
  message: message,
  async: true
)
```

From explicit retry in `MessagesController#retry`:

```ruby
AI.generate_advisor_response(
  advisor: message.sender,
  message: message,
  async: true
)
```

## Error Handling

Jobs should handle errors gracefully:

1. Catch specific errors and update state
2. Log context for debugging
3. Use `rescue_from` in ApplicationJob for global handling

## Testing

Use `assert_enqueued_with` and `perform_now`:

```ruby
test "enqueues job on message create" do
  assert_enqueued_with(job: AIRunnerJob) do
    post conversation_messages_path, params: { message: { content: "Hi" } }
  end
end
```

## Monitoring

Check job status via console:

```ruby
SolidQueue::Job.count
SolidQueue::Job.where(finished_at: nil).count # pending
SolidQueue::Job.where.not(error: nil).count   # failed
```
