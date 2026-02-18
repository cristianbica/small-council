# Plan: Conversations Phase 2 - Rules of Engagement

**Date**: 2026-02-18  
**Goal**: Add Rules of Engagement (RoE) coordination to conversations to control how advisors respond

---

## Current State Assessment

**Models**: Conversation and Message models already exist with full associations.

**Conversation model** (`app/models/conversation.rb`):
- Has `status` enum (active/archived)
- No `rules_of_engagement` field yet
- Belongs to council with `has_many :messages`

**Message model** (`app/models/message.rb`):
- Has `role` enum (user/advisor/system) and `status` enum (pending/complete/error)
- Polymorphic sender (User/Advisor)
- `content` field with validation

**Controllers**: ConversationsController and MessagesController exist with basic CRUD.

**Views**: Conversation show page displays messages and posting form.

**Missing**: Rules of Engagement field, ScribeCoordinator service, @mention parsing, advisor selection logic.

---

## Goal

Enable Rules of Engagement modes that control how advisors respond to user messages:
1. Add RoE enum to Conversation with 5 modes
2. Create UI dropdown to change RoE mode
3. Build ScribeCoordinator service to determine which advisors respond
4. Implement @mention parsing to trigger specific advisors
5. Create placeholder "thinking..." messages for selected advisors

## Non-goals

- Actual AI API integration (Phase 3)
- Real-time Turbo Stream updates (Phase 3)
- Message threading or sub-conversations
- RoE mode restrictions by user role
- Auto-switching between RoE modes
- Advisor-to-advisor direct messages

---

## Scope + Assumptions

- RoE can be changed at any time during a conversation
- @mentions work in all modes (priority override in non-on_demand modes)
- Placeholder messages use the `system` role with `pending` status
- No background jobs yet - synchronous processing
- All account users can change RoE for conversations in their councils
- Round robin tracks state in conversation metadata (no separate table)

---

## Implementation Steps

### Step 1: Database Migration - Add rules_of_engagement to conversations

**File**: `db/migrate/20260218XXXXXX_add_rules_of_engagement_to_conversations.rb`

```ruby
class AddRulesOfEngagementToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :rules_of_engagement, :string, default: "round_robin"
    add_index :conversations, :rules_of_engagement
  end
end
```

Run: `bin/rails db:migrate`

### Step 2: Update Conversation Model

**File**: `app/models/conversation.rb`

Add enum definition:

```ruby
enum :rules_of_engagement, {
  round_robin: "round_robin",
  moderated: "moderated",
  on_demand: "on_demand",
  silent: "silent",
  consensus: "consensus"
}, default: "round_robin"
```

Add methods for round robin tracking:

```ruby
# Returns the ID of the last advisor who spoke (stored in context jsonb)
def last_advisor_id
  context["last_advisor_id"]
end

# Updates context with the last advisor who spoke
def mark_advisor_spoken(advisor_id)
  update_column(:context, context.merge("last_advisor_id" => advisor_id))
end
```

### Step 3: Update Conversation Show View with RoE Dropdown

**File**: `app/views/conversations/show.html.erb`

Add RoE selector in the header section (after status badge):

```erb
<div class="flex items-center gap-2 mb-1">
  <h1 class="text-3xl font-bold"><%= @conversation.title %></h1>
  <span class="badge <%= @conversation.active? ? 'badge-success' : 'badge-ghost' %> badge-sm">
    <%= @conversation.status %>
  </span>
  
  <!-- RoE Dropdown -->
  <div class="dropdown dropdown-end">
    <label tabindex="0" class="btn btn-sm btn-outline">
      <%= @conversation.rules_of_engagement.humanize %>
      <svg class="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
      </svg>
    </label>
    <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52">
      <% Conversation.rules_of_engagement.keys.each do |mode| %>
        <li>
          <%= button_to mode.humanize, 
              conversation_path(@conversation, conversation: { rules_of_engagement: mode }),
              method: :patch,
              class: "#{@conversation.rules_of_engagement == mode ? 'active' : ''}" %>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

### Step 4: Update ConversationsController

**File**: `app/controllers/conversations_controller.rb`

Add `update` action and permit rules_of_engagement param:

```ruby
before_action :set_conversation, only: [ :show, :update ]

def update
  if @conversation.update(conversation_params)
    redirect_to @conversation, notice: "Rules of Engagement updated to #{@conversation.rules_of_engagement.humanize}."
  else
    redirect_to @conversation, alert: "Failed to update Rules of Engagement."
  end
end

def conversation_params
  params.require(:conversation).permit(:title, :rules_of_engagement)
end
```

Add update route to `config/routes.rb`:

```ruby
resources :conversations, only: [ :show, :update ] do
  resources :messages, only: [ :create ]
end
```

### Step 5: Create ScribeCoordinator Service

**File**: `app/services/scribe_coordinator.rb`

```ruby
class ScribeCoordinator
  MENTION_PATTERN = /@([a-zA-Z0-9_]+)/.freeze

  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  # Main entry point: returns array of advisors who should respond
  def determine_responders(last_message: nil)
    # Always check for @mentions first (priority override)
    mentioned = parse_mentions(last_message&.content)
    return mentioned if mentioned.any?

    case conversation.rules_of_engagement.to_sym
    when :round_robin
      next_in_round_robin
    when :moderated
      select_moderated_responder(last_message)
    when :on_demand
      [] # No mentions = no response
    when :silent
      []
    when :consensus
      conversation.council.advisors.to_a
    else
      []
    end
  end

  private

  # Parse @mentions from message content
  def parse_mentions(content)
    return [] if content.blank?

    mentioned_names = content.scan(MENTION_PATTERN).flatten.map(&:downcase)
    return [] if mentioned_names.empty?

    conversation.council.advisors.select do |advisor|
      mentioned_names.include?(advisor.name.downcase.gsub(/\s+/, "_"))
    end
  end

  # Round Robin: return next advisor in sequence
  def next_in_round_robin
    advisors = conversation.council.advisors.order(:id).to_a
    return [] if advisors.empty?

    last_id = conversation.last_advisor_id
    return [advisors.first] if last_id.nil?

    last_index = advisors.find_index { |a| a.id.to_s == last_id.to_s }
    next_index = last_index.nil? ? 0 : (last_index + 1) % advisors.count
    [advisors[next_index]]
  end

  # Moderated: simple implementation returns first advisor
  # (Phase 3: analyze content for relevance matching)
  def select_moderated_responder(last_message)
    advisors = conversation.council.advisors.to_a
    return [] if advisors.empty?

    # Simple: return advisor with most messages in this conversation
    # (placeholder for AI-based relevance matching)
    advisors.min_by { |a| conversation.messages.where(sender: a).count }
  end
end
```

### Step 6: Update MessagesController to Trigger Coordinator

**File**: `app/controllers/messages_controller.rb`

Modify `create` action to call ScribeCoordinator after saving user message:

```ruby
def create
  @message = @conversation.messages.new(message_params)
  @message.account = Current.account
  @message.sender = Current.user
  @message.role = "user"
  @message.status = "complete"

  if @message.save
    # Trigger ScribeCoordinator to determine advisor responses
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: @message)

    # Create placeholder messages for each responder
    responders.each do |advisor|
      @conversation.messages.create!(
        account: Current.account,
        sender: advisor,
        role: "system",
        content: "[#{advisor.name}] is thinking...",
        status: "pending"
      )
      # Track for round robin
      @conversation.mark_advisor_spoken(advisor.id)
    end

    redirect_to @conversation, notice: "Message posted successfully."
  else
    @messages = @conversation.messages.chronological.includes(:sender)
    @new_message = @message
    render "conversations/show", status: :unprocessable_entity
  end
end
```

### Step 7: Update Message Display for Placeholder Messages

**File**: `app/views/conversations/show.html.erb`

Update message rendering to handle pending/system messages:

```erb
<% @messages.each do |message| %>
  <% is_current_user = message.sender == Current.user %>
  <% is_pending = message.pending? %>
  
  <div class="flex <%= is_current_user ? 'justify-end' : 'justify-start' %>">
    <div class="max-w-[80%] <%= is_current_user ? 'bg-primary text-primary-content' : is_pending ? 'bg-base-200 italic opacity-70' : 'bg-base-300' %> rounded-lg p-3">
      <div class="text-xs <%= is_current_user ? 'text-primary-content/70' : 'text-base-content/60' %> mb-1">
        <%= message.sender.is_a?(Advisor) ? "Advisor: #{message.sender.name}" : message.sender.email %>
        <span class="mx-1">·</span>
        <%= time_ago_in_words(message.created_at) %> ago
        <% if is_pending %>
          <span class="badge badge-xs badge-warning ml-2">pending</span>
        <% end %>
      </div>
      <div class="whitespace-pre-wrap <%= is_pending ? 'animate-pulse' : '' %>">
        <%= message.content %>
      </div>
    </div>
  </div>
<% end %>
```

### Step 8: Create Model Tests

**File**: `test/models/conversation_test.rb`

Add tests:

```ruby
test "has rules_of_engagement enum with default round_robin" do
  conversation = conversations(:one)
  assert_equal "round_robin", conversation.rules_of_engagement
  assert conversation.round_robin?
end

test "can change rules_of_engagement" do
  conversation = conversations(:one)
  conversation.update!(rules_of_engagement: :silent)
  assert conversation.silent?
end

test "rules_of_engagement includes all expected values" do
  expected = %w[round_robin moderated on_demand silent consensus]
  assert_equal expected.sort, Conversation.rules_of_engagement.keys.sort
end

test "last_advisor_id reads from context" do
  conversation = conversations(:one)
  conversation.update!(context: { "last_advisor_id" => 42 })
  assert_equal 42, conversation.last_advisor_id
end

test "mark_advisor_spoken updates context" do
  conversation = conversations(:one)
  conversation.mark_advisor_spoken(99)
  assert_equal 99, conversation.reload.context["last_advisor_id"]
end
```

### Step 9: Create ScribeCoordinator Tests

**File**: `test/services/scribe_coordinator_test.rb`

```ruby
require "test_helper"

class ScribeCoordinatorTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @council = councils(:one)
    @conversation = conversations(:one)
    @conversation.update!(council: @council, rules_of_engagement: :round_robin)
    
    @advisor1 = advisors(:one)
    @advisor2 = advisors(:two)
    @council.advisors << [@advisor1, @advisor2]
  end

  test "round_robin returns first advisor initially" do
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_equal [@advisor1], responders
  end

  test "round_robin cycles to next advisor" do
    @conversation.mark_advisor_spoken(@advisor1.id)
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_equal [@advisor2], responders
  end

  test "round_robin wraps back to first" do
    @conversation.mark_advisor_spoken(@advisor2.id)
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_equal [@advisor1], responders
  end

  test "silent mode returns empty" do
    @conversation.update!(rules_of_engagement: :silent)
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_empty responders
  end

  test "consensus returns all advisors" do
    @conversation.update!(rules_of_engagement: :consensus)
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_equal 2, responders.count
    assert_includes responders, @advisor1
    assert_includes responders, @advisor2
  end

  test "on_demand returns empty without mentions" do
    @conversation.update!(rules_of_engagement: :on_demand)
    message = messages(:one)
    message.update!(content: "Hello without mentions")
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)
    
    assert_empty responders
  end

  test "parses @mention and returns matching advisor" do
    @advisor1.update!(name: "Test Advisor")
    message = messages(:one)
    message.update!(content: "Hey @Test_Advisor, help me out")
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)
    
    assert_equal [@advisor1], responders
  end

  test "@mentions take priority over round_robin" do
    @conversation.mark_advisor_spoken(@advisor1.id) # Would normally get advisor2
    @advisor1.update!(name: "Alpha")
    message = messages(:one)
    message.update!(content: "@Alpha please respond")
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)
    
    assert_equal [@advisor1], responders # Got advisor1 via mention, not advisor2 via round_robin
  end

  test "handles multiple @mentions" do
    @advisor1.update!(name: "Advisor One")
    @advisor2.update!(name: "Advisor Two")
    message = messages(:one)
    message.update!(content: "@Advisor_One and @Advisor_Two please help")
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders(last_message: message)
    
    assert_equal 2, responders.count
  end

  test "moderated returns first advisor when no better match" do
    @conversation.update!(rules_of_engagement: :moderated)
    
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_equal [@advisor1], responders
  end

  test "returns empty when council has no advisors" do
    @council.advisors.clear
    coordinator = ScribeCoordinator.new(@conversation)
    responders = coordinator.determine_responders
    
    assert_empty responders
  end
end
```

### Step 10: Create Integration Test

**File**: `test/integration/rules_of_engagement_flow_test.rb`

```ruby
require "test_helper"

class RulesOfEngagementFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    @council = councils(:one)
    @conversation = @council.conversations.create!(
      title: "Test RoE Flow",
      account: @account,
      user: @user,
      rules_of_engagement: :round_robin
    )
    @advisor = advisors(:one)
    @council.advisors << @advisor
    
    sign_in_as(@user)
  end

  test "user can change RoE mode from conversation page" do
    get conversation_path(@conversation)
    assert_response :success
    assert_select "span.badge", text: /round.?robin/i
    
    patch conversation_path(@conversation), params: {
      conversation: { rules_of_engagement: :silent }
    }
    
    assert_redirected_to conversation_path(@conversation)
    follow_redirect!
    assert_select "span.badge", text: /silent/i
  end

  test "posting message in round_robin creates placeholder" do
    assert_difference "Message.count", 2 do # user message + placeholder
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello advisors" }
      }
    end
    
    assert_redirected_to conversation_path(@conversation)
    
    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
    assert_equal "system", placeholder.role
    assert_equal "pending", placeholder.status
    assert_match(/thinking/, placeholder.content)
  end

  test "posting with @mention in on_demand mode" do
    @conversation.update!(rules_of_engagement: :on_demand)
    @advisor.update!(name: "Helper Bot")
    
    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "@Helper_Bot I need help" }
      }
    end
    
    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
  end

  test "silent mode does not create placeholders" do
    @conversation.update!(rules_of_engagement: :silent)
    
    assert_difference "Message.count", 1 do # only user message
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello? Anyone there?" }
      }
    end
  end

  test "consensus mode creates placeholder for all advisors" do
    advisor2 = advisors(:two)
    @council.advisors << advisor2
    @conversation.update!(rules_of_engagement: :consensus)
    
    assert_difference "Message.count", 3 do # user + 2 advisors
      post conversation_messages_path(@conversation), params: {
        message: { content: "Group discussion" }
      }
    end
    
    placeholders = Message.last(2)
    assert_equal 2, placeholders.count { |m| m.pending? }
  end

  test "changing RoE mid-conversation affects next message" do
    # First message with round_robin
    post conversation_messages_path(@conversation), params: {
      message: { content: "First message" }
    }
    
    @conversation.update!(rules_of_engagement: :silent)
    
    # Second message should not trigger advisor
    assert_difference "Message.count", 1 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Second message" }
      }
    end
  end
end
```

### Step 11: Update Documentation

**File**: `.ai/docs/features/conversations.md`

Add RoE section:

```markdown
## Rules of Engagement

Rules of Engagement (RoE) control how advisors respond to user messages.

### Modes

| Mode | Behavior |
|------|----------|
| **Round Robin** | Advisors take turns responding in sequence |
| **Moderated** | System selects most relevant advisor (Phase 2: simple, Phase 3: AI-matched) |
| **On Demand** | Only @mentioned advisors respond |
| **Silent** | No advisor responses (user-to-user mode) |
| **Consensus** | All advisors respond (internal debate mode) |

### Changing RoE

Users can change RoE at any time during a conversation using the dropdown in the conversation header.

### @Mentions

Use `@Advisor_Name` in messages to trigger specific advisors:
- Works in all modes (overrides normal RoE behavior)
- Names are case-insensitive and use underscores for spaces
- Example: `@Helper_Bot` mentions advisor named "Helper Bot"

### Placeholder Messages

When advisors are triggered to respond, a placeholder message appears:
- Content: "[Advisor Name] is thinking..."
- Status: `pending`
- Role: `system`
- Will be replaced with actual AI response in Phase 3

### Implementation

- Stored in `conversations.rules_of_engagement` (string enum)
- Default: `round_robin`
- State tracking (round robin position) in `conversations.context` jsonb
- ScribeCoordinator service determines responders
```

---

## Verification

Run this checklist after implementation:

- [ ] Migration runs successfully: `bin/rails db:migrate`
- [ ] Model tests pass: `bin/rails test test/models/conversation_test.rb`
- [ ] Service tests pass: `bin/rails test test/services/scribe_coordinator_test.rb`
- [ ] Integration tests pass: `bin/rails test test/integration/rules_of_engagement_flow_test.rb`
- [ ] All tests pass: `bin/rails test`
- [ ] Routes updated: `bin/rails routes | grep conversation` shows PATCH route
- [ ] Manual test: View conversation and see RoE dropdown showing "Round Robin"
- [ ] Manual test: Click dropdown and change to "Silent" mode
- [ ] Manual test: Post message in Silent mode - no placeholder appears
- [ ] Manual test: Change to "Round Robin", post message - placeholder appears
- [ ] Manual test: Post message with `@Advisor_Name` - mentioned advisor placeholder appears
- [ ] Manual test: Change to "Consensus" mode - all advisors get placeholders

---

## Doc Impact

- **Updated**: `.ai/docs/features/conversations.md` (add RoE section)
- **Deferred**: Pattern docs (reuse existing controller/test patterns)

---

## Rollback

If implementation fails:

1. **Database**: Rollback migration
   ```
   bin/rails db:rollback
   ```
   Then delete migration file.

2. **Remove service**: Delete `app/services/scribe_coordinator.rb`

3. **Revert model**: Remove enum and helper methods from `app/models/conversation.rb`

4. **Revert controller changes**:
   - Remove `update` action from ConversationsController
   - Remove coordinator logic from MessagesController#create
   - Revert `conversation_params` to original

5. **Revert routes**: Remove `:update` from conversations resource

6. **Revert view**: Remove RoE dropdown from `app/views/conversations/show.html.erb`

7. **Delete tests**:
   - `test/services/scribe_coordinator_test.rb`
   - `test/integration/rules_of_engagement_flow_test.rb`

---

## Unknowns / Risks

1. **Advisor name matching**: @mention parsing uses simple string matching. May need refinement for special characters or similar names.

2. **Round robin persistence**: State stored in JSONB context field. If conversation has many messages, consider extracting to separate table in future.

3. **Moderated mode AI**: Current implementation uses simple message count heuristic. Full AI relevance matching deferred to Phase 3.

4. **Concurrent updates**: Multiple users posting simultaneously could cause race conditions in round robin tracking (rare, acceptable for Phase 2).

---

**Approve this plan?**
