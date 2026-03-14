# Plan: Skip Errored Advisors + Log (Option 3)

## Problem Statement
AI providers often return errors or empty responses. This causes:
1. Conversations stall waiting for errored advisors
2. Users don't know which advisor failed
3. No way to recover without manual intervention

## Solution: Skip + Log

When an advisor errors or returns empty:
1. Mark the message as error status
2. Store error details in debug_data
3. Remove the advisor from the parent's pending_advisor_ids
4. Log the error for monitoring
5. Continue conversation lifecycle (don't block)
6. Allow manual retry later via UI

## Implementation

### 1. Error Handling in Handler

Update `ConversationResponseHandler` to catch errors:

```ruby
def handle_error(message, error)
  message.update!(
    status: "error",
    content: "Error: #{error.message}",
    debug_data: message.debug_data.merge(
      error: error.message,
      error_at: Time.current,
      error_type: error.class.name
    )
  )
  
  # Remove from pending to unblock parent
  message.parent_message&.resolve_for_advisor!(message.sender_id)
  
  # Log for monitoring
  Rails.logger.error "[AI Error] Advisor #{message.sender.name}: #{error.message}"
end
```

### 2. Update Message#solved? Logic

Error messages are considered "resolved" for the parent:

```ruby
def solved?
  # Pending advisor ids is empty OR all remaining are in error state
  pending_advisor_ids.blank? || pending_advisor_ids.empty?
end
```

Actually, with `resolve_for_advisor!` called on error, the pending list will be updated correctly.

### 3. UI Changes

Show error state in message display:
- Different styling for error messages
- Error icon/indicator
- Show retry button
- Display error details on hover/click

### 4. Retry Mechanism

Allow users to retry errored messages:

```ruby
def retry!
  return unless error?
  
  update!(
    status: "responding",
    content: "...",
    debug_data: debug_data.merge(retried_at: Time.current)
  )
  
  # Re-add to parent's pending list
  parent_message.update!(
    pending_advisor_ids: parent_message.pending_advisor_ids + [sender_id.to_s]
  )
  
  # Trigger new AI call
  AI.generate_advisor_response(
    advisor: sender,
    message: self,
    async: true
  )
end
```

### 5. Compaction Consideration

Error messages should still be compacted but marked as errors:

```
[financial] Error: Empty response from AI
```

This preserves history and shows the advisor was attempted.

## Files to Modify

1. `app/libs/ai/handlers/conversation_response_handler.rb` - Add error handling
2. `app/models/message.rb` - Add retry logic, ensure error resolves parent
3. `app/views/conversations/_message.html.erb` - Show error state, retry button
4. `app/controllers/messages_controller.rb` - Add retry action
5. Add tests for error handling flow

## Pros

1. Simple - Minimal code changes
2. Non-blocking - Conversation continues even with errors
3. Transparent - Users see which advisor errored
4. Recoverable - Can retry individual failed advisors
5. Preserves history - Error messages are part of conversation record

## Cons

1. User must manually retry - No auto-retry
2. Error messages in compaction - May clutter summary
3. No circuit breaker - Same advisor could error repeatedly

## Testing

1. Test: Error response marks message as error
2. Test: Error removes advisor from pending list
3. Test: Parent message resolves even with child errors
4. Test: Retry functionality works
5. Test: Compaction includes error messages

## Decision

Approved for implementation.
