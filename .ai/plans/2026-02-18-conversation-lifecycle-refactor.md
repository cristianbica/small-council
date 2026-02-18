# Plan: Conversation Lifecycle & RoE Refactoring

**Date**: 2026-02-18  
**Goal**: Refactor conversation management into a proper lifecycle service with individual RoE classes (Strategy Pattern)

---

## Current State Assessment

**Files inspected**:
- `app/services/scribe_coordinator.rb` (70 lines) - Contains all RoE logic with case statement
- `app/controllers/messages_controller.rb` (62 lines) - Handles message creation + triggers coordinator inline
- `app/jobs/generate_advisor_response_job.rb` (109 lines) - Generates AI responses, no lifecycle callback
- `app/models/conversation.rb` (40 lines) - Has RoE enum and `last_advisor_id` tracking
- `test/services/scribe_coordinator_test.rb` (261 lines) - Comprehensive tests for current coordinator

**Current architecture issues**:
1. **Single Responsibility Violation**: ScribeCoordinator handles 5 different RoE modes in one class with case statement
2. **Mixed Concerns**: MessagesController creates pending messages AND enqueues jobs
3. **No Lifecycle Hook**: GenerateAdvisorResponseJob completes but doesn't notify anyone for follow-up actions
4. **State Mutation**: Round robin tracking happens in controller, not in RoE logic
5. **Extensibility**: Adding new RoE mode requires modifying case statement in coordinator

**Current flow**:
```
MessagesController#create
  -> ScribeCoordinator.determine_responders (case statement)
  -> Create pending messages
  -> Enqueue GenerateAdvisorResponseJob
  -> @conversation.mark_advisor_spoken (for round_robin)
```

---

## Goal

Refactor into a proper lifecycle service with Strategy Pattern for RoE:

1. Create `ConversationLifecycle` service to orchestrate flow
2. Create individual RoE strategy classes in `app/services/roe/`
3. Move message creation and job enqueueing into lifecycle
4. Add `advisor_responded` callback for potential follow-up triggers
5. Deprecate `ScribeCoordinator` (move logic to RoE classes)
6. Update controllers and jobs to use lifecycle

## Non-goals

- No database migrations needed (using existing fields)
- No UI changes (internal refactoring only)
- No new AI features (restructure existing logic)
- No changes to RoE behavior (preserve existing functionality)
- No changes to Turbo Streams or broadcasting
- No changes to UsageRecord or cost tracking

---

## Scope + Assumptions

- All existing tests must pass after refactoring
- ScribeCoordinator tests will be migrated to RoE-specific tests
- Strategy Pattern: BaseRoE abstract class + concrete implementations
- ConversationLifecycle is the single entry point for conversation state changes
- RoE classes only determine responders, don't create messages or enqueue jobs
- Round robin state updates happen via `after_response` callback

---

## Implementation Steps

### Step 1: Create RoE Base Class

**File**: `app/services/roe/base_roe.rb`

```ruby
module RoE
  class BaseRoE
    def initialize(conversation)
      @conversation = conversation
    end

    # Must implement: given a message, which advisors respond?
    # Returns: Array of Advisor objects
    def determine_responders(message)
      raise NotImplementedError, "#{self.class} must implement determine_responders"
    end

    # Optional: called after each advisor response
    # Used by RoundRobinRoE to update state
    def after_response(advisor)
      # Override in subclasses if needed
    end

    protected

    def advisors
      @conversation.council.advisors
    end

    def conversation_history
      @conversation.messages.chronological
    end

    def parse_mentions(content)
      return [] if content.blank?

      mentioned_names = content.scan(/@([a-zA-Z0-9_\-]+)/i).flatten.map(&:downcase)
      return [] if mentioned_names.empty?

      advisors.select do |advisor|
        mentioned_names.any? { |name| name_matches?(advisor, name) }
      end
    end

    def name_matches?(advisor, mention)
      advisor_name_normalized = advisor.name.downcase.gsub(/\s+/, "_")
      advisor_name_normalized == mention.downcase ||
        advisor.name.downcase == mention.downcase
    end
  end
end
```

### Step 2: Create RoundRobinRoE

**File**: `app/services/roe/round_robin_roe.rb`

```ruby
module RoE
  class RoundRobinRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override)
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      # Get next advisor in sequence
      advisors_list = advisors.order(:id).to_a
      return [] if advisors_list.empty?

      last_spoken = @conversation.last_advisor_id

      next_index = if last_spoken
        last_index = advisors_list.find_index { |a| a.id.to_s == last_spoken.to_s }
        last_index ? (last_index + 1) % advisors_list.length : 0
      else
        0
      end

      [advisors_list[next_index]]
    end

    def after_response(advisor)
      # Update last_advisor_id in conversation context
      @conversation.mark_advisor_spoken(advisor.id)
    end
  end
end
```

### Step 3: Create OnDemandRoE

**File**: `app/services/roe/on_demand_roe.rb`

```ruby
module RoE
  class OnDemandRoE < BaseRoE
    def determine_responders(message)
      # Parse @mentions from message content
      parse_mentions(message&.content)
    end
  end
end
```

### Step 4: Create ModeratedRoE

**File**: `app/services/roe/moderated_roe.rb`

```ruby
module RoE
  class ModeratedRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override)
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      advisors_list = advisors.to_a
      return [] if advisors_list.empty?

      # Simple implementation: pick advisor based on keyword matching
      # Future: Could use AI to select most relevant advisor
      content = message&.content.to_s.downcase

      scored = advisors_list.map do |advisor|
        score = score_advisor(advisor, content)
        [advisor, score]
      end

      # Sort by score descending, return highest scoring advisor
      scored.sort_by { |_, score| -score }.first(1).map(&:first)
    end

    private

    def score_advisor(advisor, content)
      score = 0
      score += 10 if content.include?(advisor.name.downcase)

      if advisor.system_prompt.present?
        content_words = content.split
        prompt_words = advisor.system_prompt.downcase.split
        matches = content_words & prompt_words
        score += matches.length * 2
      end

      # Prefer advisors with fewer messages in this conversation
      message_count = @conversation.messages.where(sender: advisor).count
      score -= message_count * 0.5

      score
    end
  end
end
```

### Step 5: Create SilentRoE

**File**: `app/services/roe/silent_roe.rb`

```ruby
module RoE
  class SilentRoE < BaseRoE
    def determine_responders(_message)
      # Check for @mentions first (priority override even in silent mode)
      # This allows users to force a response by mentioning
      mentioned = parse_mentions(_message&.content)
      return mentioned if mentioned.any?

      [] # No one responds otherwise
    end
  end
end
```

### Step 6: Create ConsensusRoE

**File**: `app/services/roe/consensus_roe.rb`

```ruby
module RoE
  class ConsensusRoE < BaseRoE
    def determine_responders(message)
      # Check for @mentions first (priority override)
      mentioned = parse_mentions(message&.content)
      return mentioned if mentioned.any?

      # All advisors respond
      advisors.to_a
    end
  end
end
```

### Step 7: Create RoE Factory

**File**: `app/services/roe/factory.rb`

```ruby
module RoE
  class Factory
    ROE_MAP = {
      "round_robin" => RoundRobinRoE,
      "moderated" => ModeratedRoE,
      "on_demand" => OnDemandRoE,
      "silent" => SilentRoE,
      "consensus" => ConsensusRoE
    }.freeze

    def self.create(conversation)
      roe_class = ROE_MAP[conversation.rules_of_engagement]
      roe_class ||= SilentRoE # Default fallback
      roe_class.new(conversation)
    end
  end
end
```

### Step 8: Create ConversationLifecycle Service

**File**: `app/services/conversation_lifecycle.rb`

```ruby
class ConversationLifecycle
  def initialize(conversation)
    @conversation = conversation
    @roe_strategy = RoE::Factory.create(conversation)
  end

  # User posted a message
  # Creates pending messages for responders and enqueues AI jobs
  def user_posted_message(user_message)
    responders = @roe_strategy.determine_responders(user_message)

    responders.each do |advisor|
      create_pending_message_and_enqueue(advisor)
    end

    responders
  end

  # AI advisor posted a response
  # Updates message status and triggers any follow-up actions
  def advisor_responded(advisor, content, message)
    # Update message with response content
    message.update!(
      content: content,
      role: "advisor",
      status: "complete"
    )

    # Notify RoE strategy for state updates (e.g., round robin tracking)
    @roe_strategy.after_response(advisor)

    # Broadcast via Turbo Stream
    broadcast_message(message)

    # Future: Trigger next advisor if needed (e.g., multi-turn workflows)
    # Future: Check for consensus completion

    message
  rescue => e
    handle_error(message, e)
    raise unless e.is_a?(ActiveRecord::RecordInvalid)
  end

  private

  def create_pending_message_and_enqueue(advisor)
    placeholder = @conversation.messages.create!(
      account: @conversation.account,
      sender: advisor,
      role: "system",
      content: "[#{advisor.name}] is thinking...",
      status: "pending"
    )

    # Broadcast placeholder message
    broadcast_placeholder(placeholder)

    # Enqueue background job to generate actual response
    GenerateAdvisorResponseJob.perform_later(
      advisor_id: advisor.id,
      conversation_id: @conversation.id,
      message_id: placeholder.id
    )

    placeholder
  end

  def broadcast_message(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{@conversation.id}",
      target: "message_#{message.id}",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end

  def broadcast_placeholder(message)
    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{@conversation.id}",
      target: "messages",
      partial: "messages/message",
      locals: { message: message, current_user: nil }
    )
  end

  def handle_error(message, error)
    Rails.logger.error "[ConversationLifecycle] Error in advisor_responded: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")

    message.update!(
      content: "[Error: #{error.message}]",
      status: "error"
    )

    broadcast_message(message)
  end
end
```

### Step 9: Update MessagesController

**File**: `app/controllers/messages_controller.rb`

Replace the create action:

```ruby
def create
  @message = build_user_message

  if @message.save
    # Delegate to ConversationLifecycle
    lifecycle = ConversationLifecycle.new(@conversation)
    lifecycle.user_posted_message(@message)

    redirect_to @conversation, notice: "Message posted successfully."
  else
    @messages = @conversation.messages.chronological.includes(:sender)
    @new_message = @message
    render "conversations/show", status: :unprocessable_entity
  end
end

private

def build_user_message
  @conversation.messages.new(message_params).tap do |msg|
    msg.account = Current.account
    msg.sender = Current.user
    msg.role = "user"
    msg.status = "complete"
  end
end
```

Remove these lines from the old create action:
- Lines 14-36: ScribeCoordinator instantiation, responder loop, message creation, job enqueueing

### Step 10: Update GenerateAdvisorResponseJob

**File**: `app/jobs/generate_advisor_response_job.rb`

Replace the success handling section (lines 21-33):

```ruby
if result && result[:content].present?
  # Delegate to ConversationLifecycle for state management
  lifecycle = ConversationLifecycle.new(conversation)
  lifecycle.advisor_responded(advisor, result[:content], message)

  # Record usage
  create_usage_record(message, advisor, result)
else
  handle_error(message, "Empty response from AI")
end
```

Remove the direct message.update! and broadcast_message calls since lifecycle handles them now.

### Step 11: Move ScribeCoordinator Tests to RoE Tests

**File**: `test/services/roe/base_roe_test.rb` (new)

```ruby
require "test_helper"

module RoE
  class BaseRoETest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      @user = users(:one)
      set_tenant(@account)

      @space = @account.spaces.first || @account.spaces.create!(name: "General")
      @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

      @provider = @account.providers.create!(
        name: "Test Provider",
        provider_type: "openai",
        api_key: "test-key"
      )
      @llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4"
      )

      @advisor1 = @account.advisors.create!(
        name: "Test Advisor One",
        system_prompt: "You are advisor one",
        llm_model: @llm_model
      )
      @advisor2 = @account.advisors.create!(
        name: "Test Advisor Two",
        system_prompt: "You are advisor two",
        llm_model: @llm_model
      )
      @council.advisors << [@advisor1, @advisor2]

      @conversation = @account.conversations.create!(
        council: @council,
        user: @user,
        title: "Test Conversation",
        rules_of_engagement: :round_robin
      )
    end

    test "factory creates correct RoE class for each mode" do
      {
        "round_robin" => RoundRobinRoE,
        "moderated" => ModeratedRoE,
        "on_demand" => OnDemandRoE,
        "silent" => SilentRoE,
        "consensus" => ConsensusRoE
      }.each do |mode, expected_class|
        @conversation.update!(rules_of_engagement: mode)
        roe = Factory.create(@conversation)
        assert_instance_of expected_class, roe
      end
    end

    test "factory defaults to SilentRoE for unknown mode" do
      # Stub to test fallback
      def @conversation.rules_of_engagement
        "unknown_mode"
      end
      roe = Factory.create(@conversation)
      assert_instance_of SilentRoE, roe
    end
  end
end
```

**File**: `test/services/roe/round_robin_roe_test.rb` (new)

```ruby
require "test_helper"

module RoE
  class RoundRobinRoETest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      @user = users(:one)
      set_tenant(@account)

      @space = @account.spaces.first || @account.spaces.create!(name: "General")
      @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

      @provider = @account.providers.create!(
        name: "Test Provider",
        provider_type: "openai",
        api_key: "test-key"
      )
      @llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4"
      )

      @advisor1 = @account.advisors.create!(
        name: "Test Advisor One",
        system_prompt: "You are advisor one",
        llm_model: @llm_model
      )
      @advisor2 = @account.advisors.create!(
        name: "Test Advisor Two",
        system_prompt: "You are advisor two",
        llm_model: @llm_model
      )
      @council.advisors << [@advisor1, @advisor2]

      @conversation = @account.conversations.create!(
        council: @council,
        user: @user,
        title: "Test Conversation",
        rules_of_engagement: :round_robin
      )

      @roe = RoundRobinRoE.new(@conversation)
    end

    test "returns first advisor initially" do
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_equal [@advisor1], responders
    end

    test "cycles to next advisor" do
      @conversation.mark_advisor_spoken(@advisor1.id)
      message = create_message("Hello again")
      responders = @roe.determine_responders(message)
      assert_equal [@advisor2], responders
    end

    test "wraps back to first" do
      @conversation.mark_advisor_spoken(@advisor2.id)
      message = create_message("Third message")
      responders = @roe.determine_responders(message)
      assert_equal [@advisor1], responders
    end

    test "@mentions take priority over round_robin" do
      @conversation.mark_advisor_spoken(@advisor1.id)
      @advisor1.update!(name: "Alpha")
      message = create_message("@Alpha please respond")
      responders = @roe.determine_responders(message)
      assert_equal [@advisor1], responders
    end

    test "after_response updates last_advisor_id" do
      @roe.after_response(@advisor1)
      assert_equal @advisor1.id.to_s, @conversation.reload.last_advisor_id.to_s
    end

    test "returns empty when no advisors" do
      @council.advisors.clear
      message = create_message("Hello")
      responders = @roe.determine_responders(message)
      assert_empty responders
    end

    private

    def create_message(content)
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: content
      )
    end
  end
end
```

**File**: `test/services/roe/on_demand_roe_test.rb` (new)

```ruby
require "test_helper"

module RoE
  class OnDemandRoETest < ActiveSupport::TestCase
    # Similar setup as RoundRobinRoETest
    # Test: returns empty without mentions
    # Test: returns mentioned advisor
    # Test: handles multiple mentions
    # Test: name matching with underscores
  end
end
```

**File**: `test/services/roe/silent_roe_test.rb` (new)

```ruby
require "test_helper"

module RoE
  class SilentRoETest < ActiveSupport::TestCase
    # Similar setup
    # Test: returns empty normally
    # Test: returns mentioned advisors (override)
  end
end
```

**File**: `test/services/roe/consensus_roe_test.rb` (new)

```ruby
require "test_helper"

module RoE
  class ConsensusRoETest < ActiveSupport::TestCase
    # Similar setup
    # Test: returns all advisors
    # Test: @mentions override
    # Test: empty council returns empty
  end
end
```

**File**: `test/services/roe/moderated_roe_test.rb` (new)

```ruby
require "test_helper"

module RoE
  class ModeratedRoETest < ActiveSupport::TestCase
    # Similar setup
    # Test: scores advisors by keyword matching
    # Test: returns advisor with fewest messages when no keywords match
    # Test: @mentions override
  end
end
```

### Step 12: Create ConversationLifecycle Tests

**File**: `test/services/conversation_lifecycle_test.rb` (new)

```ruby
require "test_helper"

class ConversationLifecycleTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @user = users(:one)
    set_tenant(@account)

    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    @council.advisors << @advisor

    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Test Conversation",
      rules_of_engagement: :round_robin
    )

    @lifecycle = ConversationLifecycle.new(@conversation)
  end

  test "user_posted_message creates pending messages and enqueues jobs" do
    user_message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Hello"
    )

    assert_difference "Message.where(status: :pending).count", 1 do
      assert_enqueued_with(job: GenerateAdvisorResponseJob) do
        @lifecycle.user_posted_message(user_message)
      end
    end

    pending = Message.last
    assert_equal @advisor, pending.sender
    assert_equal "system", pending.role
    assert_match(/thinking/, pending.content)
  end

  test "advisor_responded updates message and broadcasts" do
    pending_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "[Test Advisor] is thinking...",
      status: "pending"
    )

    @lifecycle.advisor_responded(@advisor, "Here's my response", pending_message)

    pending_message.reload
    assert_equal "Here's my response", pending_message.content
    assert_equal "advisor", pending_message.role
    assert_equal "complete", pending_message.status
  end

  test "advisor_responded updates round_robin state" do
    @conversation.update!(rules_of_engagement: :round_robin)
    lifecycle = ConversationLifecycle.new(@conversation)

    pending_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    lifecycle.advisor_responded(@advisor, "Response", pending_message)

    assert_equal @advisor.id.to_s, @conversation.reload.last_advisor_id.to_s
  end

  test "handles error in advisor_responded" do
    pending_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    # Simulate an error
    def @advisor.name
      raise "Test error"
    end

    assert_nothing_raised do
      @lifecycle.advisor_responded(@advisor, "Response", pending_message)
    end

    pending_message.reload
    assert_equal "error", pending_message.status
    assert_match(/Test error/, pending_message.content)
  end
end
```

### Step 13: Update MessagesController Tests

**File**: `test/controllers/messages_controller_test.rb`

Update tests to verify lifecycle integration. The existing tests should still pass since behavior is preserved.

Key assertions to verify:
- Posting a message still creates pending messages
- RoE modes still work correctly
- @mentions still trigger specific advisors

### Step 14: Deprecate ScribeCoordinator

**File**: `app/services/scribe_coordinator.rb`

After verifying all tests pass, add deprecation warning and delegate to new classes:

```ruby
class ScribeCoordinator
  def initialize(conversation)
    @conversation = conversation
    @roe = RoE::Factory.create(conversation)
    Rails.logger.warn "[DEPRECATION] ScribeCoordinator is deprecated. Use ConversationLifecycle or RoE::Factory instead."
  end

  def determine_responders(last_message: nil)
    @roe.determine_responders(last_message)
  end
end
```

Then in a future PR, delete the file entirely.

---

## Verification

Run this checklist after implementation:

- [ ] All new RoE classes created in `app/services/roe/`
- [ ] Factory class maps all RoE modes correctly
- [ ] `bin/rails test test/services/roe/` - All RoE tests pass
- [ ] `bin/rails test test/services/conversation_lifecycle_test.rb` - Lifecycle tests pass
- [ ] `bin/rails test test/services/scribe_coordinator_test.rb` - Existing tests pass (via delegation)
- [ ] `bin/rails test test/controllers/messages_controller_test.rb` - Controller tests pass
- [ ] `bin/rails test` - Full suite passes (417 tests)
- [ ] Manual test: Round robin mode cycles advisors correctly
- [ ] Manual test: @mentions override RoE mode
- [ ] Manual test: Silent mode has no responses (unless mentioned)
- [ ] Manual test: Consensus mode triggers all advisors
- [ ] Manual test: AI responses update messages via lifecycle

---

## Doc Impact

- **Updated**: `.ai/docs/features/conversations.md` - Document new architecture
- **Updated**: `.ai/docs/patterns/service-objects.md` - Document Strategy Pattern usage
- **Deferred**: Remove ScribeCoordinator documentation after full deprecation

---

## Rollback

If implementation fails:

1. **Revert MessagesController** - Restore original create action with inline coordinator logic
2. **Revert GenerateAdvisorResponseJob** - Restore direct message update
3. **Keep ScribeCoordinator** - Restore original implementation (remove delegation)
4. **Delete new files**:
   - `app/services/conversation_lifecycle.rb`
   - `app/services/roe/` (entire directory)
   - `test/services/roe/` (entire directory)
   - `test/services/conversation_lifecycle_test.rb`
5. **Restore original tests** - `test/services/scribe_coordinator_test.rb`

---

## Unknowns / Risks

1. **Turbo Stream broadcasting**: Moving broadcast logic into lifecycle may change timing. Monitor for race conditions.

2. **Transaction boundaries**: Message creation and job enqueueing now happen in lifecycle. Ensure database transactions are handled correctly.

3. **Background job retry**: If `advisor_responded` fails mid-way, message may be partially updated. Job is already idempotent, but lifecycle adds new code path.

4. **RoE state mutation**: `after_response` is now called from job, not controller. This changes when round robin state updates (after AI response vs. immediately after user message).

---

**Approve this plan?**
