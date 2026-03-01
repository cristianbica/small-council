# Background Jobs

Async job processing using Solid Queue.

## Configuration

Solid Queue is configured in `config/recurring.yml` and uses database tables for job storage.

## Job Structure

```ruby
class GenerateAdvisorResponseJob < ApplicationJob
  queue_as :default

  def perform(advisor_id:, conversation_id:, message_id:)
    # Set tenant for multi-tenancy
    ActsAsTenant.current_tenant = Advisor.find(advisor_id).account

    # Do work...

  ensure
    ActsAsTenant.current_tenant = nil
  end
end
```

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

From controllers:

```ruby
GenerateAdvisorResponseJob.perform_later(
  advisor_id: advisor.id,
  conversation_id: conversation.id,
  message_id: placeholder.id
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
  assert_enqueued_with(job: GenerateAdvisorResponseJob) do
    post conversation_messages_path, params: { message: { content: "Hi" } }
  end
end

test "updates message status" do
  mock_response = AI::Model::Response.new(content: "Hi", usage: AI::Model::TokenUsage.new(input: 5, output: 3))
  mock_client = mock("AI::Client")
  mock_client.stubs(:chat).returns(mock_response)
  AI::Client.stubs(:new).returns(mock_client)
  GenerateAdvisorResponseJob.perform_now(advisor_id: @advisor.id, conversation_id: @conversation.id, message_id: @message.id)
  assert @message.reload.complete?
end
```

## Monitoring

Check job status via console:

```ruby
SolidQueue::Job.count
SolidQueue::Job.where(finished_at: nil).count # pending
SolidQueue::Job.where.not(error: nil).count   # failed
```
