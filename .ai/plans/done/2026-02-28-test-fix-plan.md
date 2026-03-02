# Test Fix Plan

## Phase 1: Fix Test Failures (26 failures)

### 1. BaseContextBuilder - Missing nil validation (3 tests)
**Files:** 
- `app/libs/ai/context_builders/base_context_builder.rb`
- `test/ai/unit/context_builders/base_context_builder_test.rb:188`
- `test/ai/unit/context_builders/conversation_context_builder_test.rb:132`
- `test/ai/unit/context_builders/scribe_context_builder_test.rb:128`

**Issue:** `validate_space!` doesn't raise when space is nil
**Fix:** Make `validate_space!` actually raise `ArgumentError`

### 2. MessagesControllerTest - Jobs not enqueued (2 tests)
**Files:**
- `test/controllers/messages_controller_test.rb:77,97`

**Issue:** Council advisors not being added as conversation participants
**Fix:** Add advisors as conversation participants in test setup

### 3. ConversationLifecycleTest - Invite command not working (1 test)
**Files:**
- `app/services/conversation_lifecycle.rb`
- `test/services/conversation_lifecycle_test.rb:154`

**Issue:** Command execution flow doesn't properly reload advisors
**Fix:** Ensure command execution reloads conversation advisors properly

### 4. InviteCommandTest - Database/test isolation issues (6 tests)
**Files:**
- `test/services/commands/invite_command_test.rb`

**Issue:** Deadlocks and foreign key violations during test setup
**Fix:** Use fixtures or improve test isolation

### 5. ConversationsControllerTest - Multiple issues (8 tests)
**Files:**
- `test/controllers/conversations_controller_test.rb`

**Issues:**
- Error messages don't match: "Only the conversation starter" vs "conversation starter or council creator"
- `approve_summary` sets status to `resolved` but code sets `concluding` first, then `resolved`
- Update test expects title change but validation fails
- Destroy fails for council creator

**Fix:** 
- Update error message expectations to match actual controller messages
- Verify approve_summary flow
- Check conversation validation logic

### 6. RulesOfEngagementFlowTest - Legacy RoE types (2 tests)
**Files:**
- `test/integration/rules_of_engagement_flow_test.rb`

**Issue:** Using legacy RoE types (round_robin, silent, on_demand, consensus) instead of new types (open, consensus, brainstorming)
**Fix:** Update tests to use new RoE types

### 7. AI ClientTest - Mock issues (2 tests)
**Files:**
- `test/ai/unit/client_test.rb`

**Issue:** Mock setup/teardown issues with Mocha
**Fix:** Fix mock setup

## Phase 2: Add New Tests for Coverage

### Coverage Targets
- Current: 63.37%
- Target: >90%

### Files to Add Tests For:

1. **app/services/conversation_lifecycle.rb** (all branches)
   - Depth enforcement
   - @all mention expansion  
   - Command handling
   - Scribe follow-up limits
   - Error handling

2. **app/services/commands/*.rb** (all scenarios)
   - Edge cases
   - Invalid commands
   - Permission checks

3. **app/models/conversation_participant.rb**
   - Validation
   - Ordering
   - Role enum

4. **app/models/message.rb** (threading methods)
   - Depth calculation
   - Solved state
   - Parent/child relationships
   - Pending advisor tracking

5. **Integration Tests**
   - User creates adhoc conversation -> invites advisors -> posts message -> advisors respond
   - Council meeting flow
   - Scribe follow-up flow (max 3 consecutive, reset on user message)
   - Depth limit enforcement
   - @all mention expansion
   - RoE type enforcement

## Implementation Order

1. Fix base context builder validation
2. Fix controller test setup (participants)
3. Fix error message assertions
4. Fix RoE flow tests
5. Fix command tests
6. Add missing model tests
7. Add integration tests
8. Verify coverage >90%
