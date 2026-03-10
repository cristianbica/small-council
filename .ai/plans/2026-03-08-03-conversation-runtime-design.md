# ConversationRuntime Design

Date: 2026-03-08
Status: Draft

## Core Concept

ConversationRuntime is a **stateless, functional orchestrator** that determines:
1. Who should respond next
2. What the conversation state is
3. When a round/session is complete

It does NOT:
- Enqueue jobs
- Broadcast updates
- Modify messages directly

Those are the caller's responsibility (Job + Handler).

## State Machine

### Open Mode

```
States: idle → waiting_for_advisors → complete

Trigger: User posts message
  ↓
Determine mentioned advisors (or single advisor if implicit)
  ↓
Create pending placeholders
  ↓
For each advisor (turn-based):
  Enqueue job
  Wait for completion
  ↓
When last advisor completes → complete
```

**Key behaviors**:
- Single round only
- No scribe involvement (unless scribe is the single advisor)
- User must @mention (or implicit if 1-on-1)

### Consensus Mode

```
States: 
  idle → awaiting_user_topic → awaiting_confirmation → 
  advisor_round → evaluating → [consensus_reached|next_round] → 
  conclusion → complete

Trigger: User posts message with topic/task
  ↓
Scribe analyzes request
  ↓
Scribe posts confirmation question to user
  ↓
User confirms (via reply)
  ↓
Round 1 begins:
  Scribe mentions advisors (subset)
  ↓
Advisors respond (turn-based, not all required)
  ↓
Scribe evaluates responses
  ↓
If consensus reached:
  Scribe posts conclusion → complete
Else if rounds < soft_limit:
  Next round → Scribe mentions advisors
Else if rounds >= hard_limit:
  Scribe posts "max rounds reached" conclusion → complete
```

**Key behaviors**:
- Scribe is the driver
- Soft limit (default 5): Scribe tries to conclude
- Hard limit (15): Force conclusion
- Scribe can mention subset of advisors
- Not all advisors need to respond

### Brainstorming Mode

```
States:
  idle → awaiting_user_topic → awaiting_confirmation →
  idea_collection → evaluation → [conclusion|next_round] →
  final_synthesis → complete

Trigger: User posts message with topic + evaluation framework
  ↓
Scribe analyzes request
  ↓
Scribe posts confirmation question to user
  ↓
User confirms (via reply)
  ↓
Round 1 begins:
  Scribe triggers advisors for ideas
  ↓
Advisors respond with ideas (turn-based)
  ↓
Scribe evaluates ideas (might ask other advisors for opinions on specific ideas)
  ↓
If rounds < soft_limit:
  Next round → Scribe requests more ideas or opinions
Else:
  Scribe formulates final conclusion → complete
```

**Key behaviors**:
- Similar to consensus but focused on ideas
- Scribe can drill into specific ideas by asking other advisors
- Evaluation framework guides scribe's synthesis

## Data Model Extensions

### Conversation State Tracking

We need to track session state for consensus/brainstorming modes.

Option A: Extend `conversations` table
```ruby
add_column :conversations, :session_state, :jsonb, default: {}
# session_state: {
#   mode: "consensus",
#   phase: "advisor_round", # awaiting_confirmation, advisor_round, evaluating, conclusion
#   round_number: 3,
#   soft_limit: 5,
#   hard_limit: 15,
#   initiated_by_message_id: 123,
#   context_summary: "Discuss Q3 budget allocation..."
# }
```

Option B: Session object
```ruby
class ConversationSession < ApplicationRecord
  belongs_to :conversation
  belongs_to :initiating_message
  
  enum :mode, { consensus: "consensus", brainstorming: "brainstorming" }
  enum :phase, { 
    awaiting_confirmation: "awaiting_confirmation",
    collecting_responses: "collecting_responses", 
    evaluating: "evaluating",
    concluded: "concluded"
  }
  
  attribute :round_number, default: 0
  attribute :soft_limit, default: 5
  attribute :hard_limit, default: 15
end
```

**Recommendation**: Option B (Session object)
- Cleaner separation
- Can have multiple sessions per conversation over time
- Easier to query and audit

### Message Role Extensions

Need to distinguish scribe's different roles:

```ruby
enum :role, {
  user: "user",
  advisor: "advisor",
  scribe: "scribe",  # Scribe acting as participant
  system: "system"
}

# OR use a separate field:
enum :message_type, {
  standard: "standard",
  confirmation_request: "confirmation_request",  # Scribe asking user to confirm
  confirmation_response: "confirmation_response", # User confirming
  evaluation: "evaluation",  # Scribe evaluating round
  conclusion: "conclusion"   # Scribe final summary
}
```

## ConversationRuntime Interface

```ruby
class ConversationRuntime
  def initialize(conversation)
    @conversation = conversation
    @session = find_or_initialize_session
  end
  
  # === Incoming Message Processing ===
  
  # Main entry point: user or advisor posted a message
  # Returns: Action object describing what to do next
  def process_message(message)
    case @conversation.roe_type
    when "open"
      process_open_mode(message)
    when "consensus"
      process_consensus_mode(message)
    when "brainstorming"
      process_brainstorming_mode(message)
    end
  end
  
  # === State Queries ===
  
  # What's the current session state?
  def session_state
    @session&.state || :idle
  end
  
  # Who should respond next?
  def next_responder
    return nil unless @session
    
    case @session.phase
    when "awaiting_confirmation"
      @conversation.user  # User needs to confirm
    when "collecting_responses"
      next_advisor_in_turn
    when "evaluating"
      @conversation.scribe_advisor
    end
  end
  
  # Is the session complete?
  def complete?
    @session&.concluded? || false
  end
  
  private
  
  # === Open Mode Processing ===
  
  def process_open_mode(message)
    return Action.nothing unless message.user?
    
    advisors = determine_mentioned_advisors(message)
    return Action.nothing if advisors.empty?
    
    # Create pending messages for each advisor
    pending = advisors.map do |advisor|
      create_pending_message(advisor, message)
    end
    
    Action.enqueue_advisors(pending, turn_based: true)
  end
  
  # === Consensus Mode Processing ===
  
  def process_consensus_mode(message)
    case @session.phase
    when nil, "idle"
      start_consensus_session(message) if message.user?
    when "awaiting_confirmation"
      handle_confirmation_response(message)
    when "collecting_responses"
      handle_advisor_response(message)
    when "evaluating"
      handle_scribe_evaluation(message)
    end
  end
  
  def start_consensus_session(message)
    # Create session
    @session = ConversationSession.create!(
      conversation: @conversation,
      mode: "consensus",
      phase: "awaiting_confirmation",
      initiating_message: message,
      context_summary: message.content
    )
    
    # Scribe will ask for confirmation
    Action.enqueue_scribe_confirmation(@session, message)
  end
  
  def handle_confirmation_response(message)
    return unless message.user?
    return unless message.confirming_session?(@session)
    
    @session.update!(phase: "collecting_responses", round_number: 1)
    
    # Scribe starts round 1
    Action.enqueue_scribe_round_start(@session, round: 1)
  end
  
  def handle_advisor_response(message)
    return unless message.advisor?
    
    # Mark advisor as responded
    @session.record_response(message.sender)
    
    # Check if scribe should evaluate
    if @session.ready_for_evaluation?
      @session.update!(phase: "evaluating")
      Action.enqueue_scribe_evaluation(@session)
    else
      # More advisors to respond
      Action.enqueue_next_advisor(@session)
    end
  end
  
  def handle_scribe_evaluation(message)
    return unless message.scribe?
    
    if consensus_reached?(message)
      @session.update!(phase: "concluded", concluded_at: Time.current)
      Action.session_complete(@session)
    elsif @session.round_number >= @session.hard_limit
      @session.update!(phase: "concluded", concluded_at: Time.current)
      Action.session_complete(@session, reason: :hard_limit_reached)
    else
      # Next round
      @session.update!(
        phase: "collecting_responses", 
        round_number: @session.round_number + 1
      )
      Action.enqueue_scribe_round_start(@session, round: @session.round_number)
    end
  end
  
  # === Brainstorming Mode Processing ===
  
  # Similar to consensus but with idea-focused phases
  def process_brainstorming_mode(message)
    # ... similar structure with idea_collection phase
  end
end
```

## Action Objects

Actions are pure data returned by Runtime, interpreted by the Job:

```ruby
class ConversationRuntime::Action
  def self.nothing
    new(:nothing)
  end
  
  def self.enqueue_advisors(pending_messages, turn_based: true)
    new(:enqueue_advisors, pending_messages: pending_messages, turn_based: turn_based)
  end
  
  def self.enqueue_scribe_confirmation(session, message)
    new(:enqueue_scribe, session: session, task: :confirmation, context: message)
  end
  
  def self.enqueue_scribe_round_start(session, round:)
    new(:enqueue_scribe, session: session, task: :round_start, round: round)
  end
  
  def self.enqueue_scribe_evaluation(session)
    new(:enqueue_scribe, session: session, task: :evaluation)
  end
  
  def self.enqueue_next_advisor(session)
    new(:enqueue_next_advisor, session: session)
  end
  
  def self.session_complete(session, reason: :consensus)
    new(:session_complete, session: session, reason: reason)
  end
  
  attr_reader :type, :params
  
  def initialize(type, **params)
    @type = type
    @params = params
  end
end
```

## Job Integration

```ruby
class GenerateAdvisorResponseJob < ApplicationJob
  def perform(advisor_id:, conversation_id:, message_id:, session_id: nil, task: nil)
    setup_tenant_and_space
    
    runtime = ConversationRuntime.new(conversation)
    
    # Generate response based on task type
    case task
    when :confirmation
      generate_scribe_confirmation(runtime.session)
    when :round_start
      generate_scribe_round_start(runtime.session)
    when :evaluation
      generate_scribe_evaluation(runtime.session)
    else
      generate_standard_advisor_response(advisor, message)
    end
    
    # Process completion through runtime
    action = runtime.process_message(message.reload)
    execute_action(action)
  end
  
  private
  
  def execute_action(action)
    case action.type
    when :nothing
      # Do nothing
    when :enqueue_advisors
      if action.params[:turn_based]
        enqueue_next_advisor(action.params[:pending_messages].first)
      else
        action.params[:pending_messages].each { |pm| enqueue_next_advisor(pm) }
      end
    when :enqueue_scribe
      enqueue_scribe_task(action.params)
    when :enqueue_next_advisor
      advisor = runtime.next_responder
      GenerateAdvisorResponseJob.perform_later(...)
    when :session_complete
      broadcast_session_complete(action.params[:session])
    end
  end
end
```

## Open Questions

1. **Session persistence**: Store in DB or derive from messages?
2. **User confirmation**: How does user confirm? Reply "yes" or click button?
3. **Advisor selection**: How does scribe decide which advisors to mention each round?
4. **Consensus detection**: How does scribe signal consensus reached vs next round?
5. **Interruption**: Can user interrupt a consensus/brainstorming session?
