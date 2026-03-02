# Conversation System Refactoring Plan

## Goals

- Support discussions with any advisor outside councils, while keeping the scribe present in all conversations.
- Unify conversation lifecycle and RoE into simpler, predictable behavior.

## Proposed Changes (Concept)

### Conversation Types

- **Council meeting**: tied to a council (preset advisor group).
- **Adhoc**: non‑council conversation where the user invites advisors.

### Participants

- Every conversation has a participant list (advisors).
- The scribe is automatically present in every conversation.
- Users can invite any advisor to any conversation.

### Rules of Engagement (RoE)

1. **Open**: advisors respond when mentioned; `@all` / `@everyone` is a use‑case that triggers all advisors to respond individually.
2. **Consensus**: advisors discuss until they agree.
3. **Brainstorming**: advisors iterate on ideas until the user says "done".

Removed: round‑robin, moderated, silent.

### Conversation Lifecycle (Concept)

- Each message has `pending_advisor_ids` derived from mentions.
- A message is “solved” when `pending_advisor_ids` is empty.
- Replies reference `in_reply_to_id` and can include mentions.
- Reply graphs have a max depth controlled by RoE:
  - Open: max depth = 1
  - Brainstorming / Consensus: max depth = 2
- After a root message is solved, the scribe may decide next steps.
  - The scribe can summarize for the user or request more input from advisors.
  - Scribe follow‑ups are new root messages (not replies).
  - The scribe can initiate at most 3 consecutive interactions without user input.

## Implementation Plan

---

### Phase 1: Database & Models

**Step 1.1: Create migration for schema changes**

```ruby
# db/migrate/xxx_add_conversation_refactor.rb

# Add conversation_type to conversations
add_column :conversations, :conversation_type, :string, null: false, default: 'council_meeting'
add_index :conversations, :conversation_type

# Make council_id nullable for adhoc conversations
change_column_null :conversations, :council_id, true

# Create conversation_participants join table
create_table :conversation_participants do |t|
  t.references :conversation, null: false, foreign_key: true
  t.references :advisor, null: false, foreign_key: true
  t.string :role, null: false, default: 'advisor'  # 'advisor' | 'scribe'
  t.integer :position, default: 0
  t.timestamps
end
add_index :conversation_participants, [:conversation_id, :advisor_id], unique: true

# Add message threading and pending state
add_column :messages, :in_reply_to_id, :bigint, foreign_key: { to_table: :messages }
add_index :messages, :in_reply_to_id
add_column :messages, :pending_advisor_ids, :jsonb, default: []
add_index :messages, :pending_advisor_ids, using: :gin

# Add scribe flag to advisors (instead of name detection)
add_column :advisors, :is_scribe, :boolean, default: false
add_index :advisors, :is_scribe
```

**Step 1.2: Update Conversation model**

- Replace `belongs_to :council` with optional association
- Add `has_many :conversation_participants`
- Add `has_many :advisors, through: :conversation_participants`
- Add enum for `conversation_type: [:council_meeting, :adhoc]`
- Remove `rules_of_engagement` enum
- Add method to get scribe participant
- Add validation: must have at least 1 advisor + scribe

**Step 1.3: Create ConversationParticipant model**

- Standard join table model
- Belongs to conversation and advisor
- Enum for role: `[:advisor, :scribe]`
- Default scope excludes scribe for advisor listings

**Step 1.4: Update Message model**

- Add `belongs_to :parent_message, class_name: 'Message', foreign_key: 'in_reply_to_id', optional: true`
- Add `has_many :replies, class_name: 'Message', foreign_key: 'in_reply_to_id'`
- Add methods to manage `pending_advisor_ids` array
- Add `solved?` method (pending_advisor_ids empty)
- Add `depth` method to calculate reply graph depth

**Step 1.5: Update Advisor model**

- Update `scribe?` method to use `is_scribe` flag
- Add `has_many :conversation_participants`
- Add `has_many :conversations, through: :conversation_participants`

**Step 1.6: Update Council model**

- Keep `has_many :conversations` but handle both types
- Ensure scribe assignment creates ConversationParticipant, not just CouncilAdvisor

**Step 1.7: Create data migration**

- Set all existing conversations to `conversation_type = 'council_meeting'`
- Populate `conversation_participants` for existing conversations:
  - Create participant for each council advisor with role 'advisor'
  - Create participant for scribe with role 'scribe'
- Backfill `is_scribe = true` for advisors matching scribe name pattern

---

### Phase 2: Command System

**Step 2.1: Create CommandParser service**

```ruby
# app/services/command_parser.rb
class CommandParser
  COMMANDS = {
    'invite' => Commands::InviteCommand
  }.freeze

  def self.parse(content)
    return nil unless content.start_with?('/')
    
    parts = content[1..].split
    command_name = parts.first.downcase
    args = parts[1..]
    
    command_class = COMMANDS[command_name]
    return nil unless command_class
    
    command_class.new(args)
  end
end
```

**Step 2.2: Create base command class**

```ruby
# app/services/commands/base_command.rb
module Commands
  class BaseCommand
    attr_reader :args, :errors
    
    def initialize(args)
      @args = args
      @errors = []
    end
    
    def valid?
      validate
      @errors.empty?
    end
    
    def execute(conversation:, user:)
      raise NotImplementedError
    end
    
    protected
    
    def validate
      raise NotImplementedError
    end
  end
end
```

**Step 2.3: Create InviteCommand**

```ruby
# app/services/commands/invite_command.rb
module Commands
  class InviteCommand < BaseCommand
    def validate
      if args.empty?
        @errors << "Usage: /invite @advisor_name"
        return
      end
      
      mention = args.first
      unless mention.start_with?('@')
        @errors << "Please mention an advisor with @advisor_name"
      end
    end
    
    def execute(conversation:, user:)
      advisor_name = args.first.sub('@', '')
      advisor = conversation.account.advisors.find_by("LOWER(name) = ?", advisor_name.downcase)
      
      if advisor.nil?
        return { success: false, message: "Advisor '#{advisor_name}' not found" }
      end
      
      if conversation.advisors.include?(advisor)
        return { success: false, message: "#{advisor.name} is already in this conversation" }
      end
      
      conversation.conversation_participants.create!(
        advisor: advisor,
        role: 'advisor'
      )
      
      { success: true, message: "#{advisor.name} has been invited" }
    end
  end
end
```

---

### Phase 3: Conversation Lifecycle Rewrite

**Step 3.1: Create new ConversationLifecycle service**

Replace the existing service with a state-machine approach:

```ruby
# app/services/conversation_lifecycle.rb
class ConversationLifecycle
  MAX_SCRIBE_INITIATED = 3
  
  def initialize(conversation)
    @conversation = conversation
    @scribe_initiated_count = 0
  end
  
  # Called when user posts a message
  def user_posted_message(user_message)
    return unless user_message.persisted?
    
    # Check for commands
    command = CommandParser.parse(user_message.content)
    if command
      handle_command(command, user_message)
      return
    end
    
    # Normal message flow
    mentioned_advisors = parse_mentions(user_message.content)
    
    # For Open RoE with @all, expand to all participants
    if should_expand_all_mentions?(user_message)
      mentioned_advisors = @conversation.advisors.to_a
    end
    
    # Populate pending_advisor_ids
    user_message.update!(
      pending_advisor_ids: mentioned_advisors.map(&:id)
    )
    
    # Queue responses
    mentioned_advisors.each do |advisor|
      create_pending_message_and_enqueue(advisor, user_message)
    end
  end
  
  # Called when advisor responds
  def advisor_responded(advisor_response_message)
    parent_message = advisor_response_message.parent_message
    return unless parent_message
    
    # Remove advisor from pending list
    parent_message.pending_advisor_ids.delete(advisor_response_message.sender_id)
    parent_message.save!
    
    # Check if parent is now solved
    if parent_message.solved?
      handle_message_solved(parent_message)
    end
  end
  
  private
  
  def handle_message_solved(message)
    # Only scribe can initiate follow-ups for non-root messages
    return unless message.parent_message.nil?  # Only for root messages
    
    # Check scribe initiated limit
    if @scribe_initiated_count >= MAX_SCRIBE_INITIATED
      return
    end
    
    # Let scribe decide next steps
    scribe = @conversation.scribe_participant&.advisor
    return unless scribe
    
    # Create scribe follow-up message
    scribe_message = @conversation.messages.create!(
      sender: scribe,
      role: 'advisor',
      content: '[Scribe is evaluating...]',
      status: 'pending'
    )
    
    @scribe_initiated_count += 1
    GenerateAdvisorResponseJob.perform_later(
      advisor_id: scribe.id,
      conversation_id: @conversation.id,
      message_id: scribe_message.id,
      is_scribe_followup: true
    )
  end
  
  def handle_command(command, user_message)
    unless command.valid?
      create_system_message("Command error: #{command.errors.join(', ')}")
      return
    end
    
    result = command.execute(conversation: @conversation, user: user_message.sender)
    create_system_message(result[:message])
  end
  
  def create_pending_message_and_enqueue(advisor, parent_message)
    message = @conversation.messages.create!(
      sender: advisor,
      role: 'advisor',
      parent_message: parent_message,
      content: "[#{advisor.name}] is thinking...",
      status: 'pending'
    )
    
    # Check depth limit
    depth = calculate_depth(message)
    max_depth = max_depth_for_roe(@conversation)
    
    if depth > max_depth
      message.update!(status: 'cancelled', content: '[Response skipped: depth limit reached]')
      return
    end
    
    GenerateAdvisorResponseJob.perform_later(
      advisor_id: advisor.id,
      conversation_id: @conversation.id,
      message_id: message.id
    )
  end
  
  def calculate_depth(message)
    depth = 0
    current = message
    while current.parent_message
      depth += 1
      current = current.parent_message
    end
    depth
  end
  
  def max_depth_for_roe(conversation)
    case conversation.roe_type  # New column needed
    when 'open'
      1
    when 'consensus', 'brainstorming'
      2
    else
      1
    end
  end
  
  def should_expand_all_mentions?(message)
    return false unless message.content.match?(/@all|@everyone/i)
    @conversation.roe_type == 'open'
  end
  
  def parse_mentions(content)
    return [] if content.blank?
    
    mentioned_names = content.scan(/@([a-zA-Z0-9_\-]+)/i).flatten.map(&:downcase)
    
    @conversation.advisors.select do |advisor|
      mentioned_names.any? { |name| name_matches?(advisor, name) }
    end
  end
  
  def name_matches?(advisor, mention)
    advisor_name_normalized = advisor.name.downcase.gsub(/[\s\-]+/, '_')
    mention_normalized = mention.downcase.gsub(/[\s\-]+/, '_')
    advisor_name_normalized == mention_normalized || 
      advisor.name.downcase.include?(mention.downcase)
  end
end
```

**Step 3.2: Update GenerateAdvisorResponseJob**

- Add `is_scribe_followup` parameter
- Update AI prompt generation to handle scribe follow-up mode
- Handle tool calls properly in the response flow

**Step 3.3: Remove old RoE services**

Delete:
- `app/services/roe.rb`
- `app/services/roe/base_roe.rb`
- `app/services/roe/factory.rb`
- `app/services/roe/round_robin_roe.rb`
- `app/services/roe/moderated_roe.rb`
- `app/services/roe/on_demand_roe.rb`
- `app/services/roe/silent_roe.rb`
- `app/services/roe/consensus_roe.rb`

**Step 3.4: Update Conversation model with RoE methods**

Replace `rules_of_engagement` with `roe_type`:
- Enum: `roe_type: [:open, :consensus, :brainstorming]`
- Remove old RoE enum
- Update any UI that references rules_of_engagement

---

### Phase 4: Controllers & Routes

**Step 4.1: Update ConversationsController**

- Modify `create` action to handle both council_meeting and adhoc types
- For adhoc: require `advisor_ids` param, auto-add scribe
- For council_meeting: use existing council flow
- Remove RoE selection from params (use default or derive from type)

**Step 4.2: Add new routes**

```ruby
resources :conversations do
  resources :messages, only: [:create]
  member do
    post :finish
    post :approve_summary
    post :reject_summary
    post :invite_advisor  # New action for UI button
  end
  
  collection do
    get :adhoc  # List only adhoc conversations
  end
end
```

**Step 4.3: Update MessagesController**

- Keep existing create flow
- Ensure it calls `ConversationLifecycle#user_posted_message`
- Handle command validation errors gracefully

---

### Phase 5: UI/UX Changes

**Step 5.1: Add "Conversations" menu item**

- Add to main navigation
- Links to `adhoc_conversations_path`
- Shows only adhoc conversation history

**Step 5.2: Update conversation creation form**

- Add toggle: "Create council meeting" vs "Start conversation"
- For adhoc: show advisor multi-select (exclude scribe)
- Remove RoE selection (now handled by type)

**Step 5.3: Add invite UI**

- Add "Invite Advisor" button in conversation header
- Opens modal with advisor selection
- Alternative: type `/invite @advisor` in message input

**Step 5.4: Update conversation sidebar**

- Show participant list with avatars
- Scribe always shown first with distinct styling
- Show typing indicators based on pending messages

**Step 5.5: Update message display**

- Show reply threads visually (indent or thread line)
- Show pending status with animated indicator
- Show "solved" state checkmark for messages

---

### Phase 6: AI Context & Prompts

**Step 6.1: Update context builders**

- `ConversationContextBuilder`: include participant list, exclude council-only context
- Update system prompts for new RoE behavior
- Add mention detection instructions for Open RoE

**Step 6.2: Update scribe system prompt**

- Add instructions for scribe follow-up behavior
- Explain depth limits and when to summarize vs. continue
- Add instructions for `/invite` command if scribe can suggest invitations

---

### Phase 7: Testing & Quality

**Step 7.1: Model tests**

- Test ConversationParticipant validations
- Test Conversation type enum and scopes
- Test Message depth calculation and pending state
- Test scribe auto-presence

**Step 7.2: Service tests**

- Test CommandParser with valid/invalid commands
- Test InviteCommand with edge cases
- Test ConversationLifecycle flow:
  - User message → pending creation
  - Advisor response → pending clearance
  - Depth enforcement
  - Scribe follow-up initiation
  - Max scribe limit

**Step 7.3: Integration tests**

- End-to-end conversation flow
- Command execution flow
- Council meeting creation flow
- Adhoc conversation creation flow

**Step 7.4: Migration tests**

- Test data migration on staging copy
- Verify participant creation for all conversations
- Verify scribe flag backfill

---

### Phase 8: Deployment

**Step 8.1: Pre-deployment**

- Run migrations in staging
- Verify all tests pass
- Create rollback plan

**Step 8.2: Deployment order**

1. Deploy Phase 1 (migrations only, no code changes)
2. Run data migrations
3. Deploy Phase 2-7 code changes
4. Monitor for errors

**Step 8.3: Post-deployment**

- Verify existing conversations work
- Test new adhoc conversation creation
- Monitor job queue for errors
- Check command parsing works

---

## Decisions

1. Council meetings remain a distinct conversation type.
2. Add `/` commands; first command is `/invite @advisor`.
   - Any message starting with `/` is treated as a system command.
   - Commands are strictly validated before execution.
3. Archived conversations preserve their participant snapshot.

## UX Notes

- Council conversations: UI/UX remains unchanged.
- Adhoc conversations: same layout, but the left sidebar shows only adhoc history and is labeled “Conversations”.

## Files to Modify/Create

### New Files
- `app/models/conversation_participant.rb`
- `app/services/command_parser.rb`
- `app/services/commands/base_command.rb`
- `app/services/commands/invite_command.rb`
- `db/migrate/xxx_add_conversation_refactor.rb`
- `db/migrate/xxx_backfill_conversation_data.rb`

### Modified Files
- `app/models/conversation.rb`
- `app/models/message.rb`
- `app/models/advisor.rb`
- `app/models/council.rb`
- `app/services/conversation_lifecycle.rb` (rewrite)
- `app/jobs/generate_advisor_response_job.rb`
- `app/controllers/conversations_controller.rb`
- `app/controllers/messages_controller.rb`
- `config/routes.rb`
- Various view files

### Deleted Files
- `app/services/roe.rb`
- `app/services/roe/*.rb` (all 7 files)
