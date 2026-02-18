# TODO

## Security & Correctness Audit Follow-ups

**Status**: All critical and high priority security fixes completed.

### Encryption at Rest ✅
- [x] Messages content encrypted at rest
- [x] Conversation memories encrypted at rest
- [x] Advisor system prompts encrypted at rest
- [x] Rails Active Record Encryption configured

---

## Remaining Features to Implement

### Phase 3: Meeting Lifecycle ✅ IMPLEMENTED

#### 1. Conversation Resolution ✅
- [x] Add `status` enum to conversations (active, concluding, resolved, archived)
- [x] "Resolve/End Conversation" button in conversation UI (for On Demand, Silent modes)
- [x] Auto-conclusion for Consensus, Round Robin, Moderated modes
- [x] Resolved conversations become read-only (no new messages)
- [x] Visual indicator (badge/icon) for resolved/concluding conversations

#### 2. AI Memory Generation ✅
- [x] On conversation resolution, trigger background job
- [x] AI analyzes full conversation transcript
- [x] Store generated memory in conversation.draft_memory
- [x] Rich AI-generated summary with structured fields (key decisions, action items, insights, open questions)

#### 3. User Review & Edit ✅
- [x] Display AI-generated memory to user for review
- [x] Text area for editing/saving changes
- [x] Accept/Reject options (approve_summary, reject_summary actions)
- [x] Option to regenerate with different focus

#### 4. Persist to Space Memory ✅
- [x] Save approved memory to conversation.memory
- [x] Link back to source conversation
- [x] Append to space.memory (cumulative knowledge)
- [x] Memory browser/search in space view
- [ ] **PENDING**: Deduplication/similarity detection for repeated insights

---

### Phase 4: Usage Dashboard (NOT STARTED)

#### 1. Cost Visualization
- [ ] Monthly/weekly cost charts
- [ ] Breakdown by:
  - Provider (OpenAI, Anthropic, etc.)
  - Model (GPT-4, Claude 3, etc.)
  - Council (which councils use most)
  - Advisor (which advisors are most active)

#### 2. Token Usage Metrics
- [ ] Input vs output token ratios
- [ ] Average tokens per conversation
- [ ] Peak usage times

#### 3. Billing Observability
- [ ] Estimated monthly cost projection
- [ ] Budget alerts/thresholds
- [ ] Export usage reports (CSV)
- [ ] Cost per conversation/advisor

#### 4. Dashboard UI
- [ ] New `/usage` route
- [ ] Charts (use Chart.js or similar)
- [ ] Date range picker
- [ ] Filter by space/council/advisor

---

### Dashboard Enhancements (NOT STARTED)

#### 1. Recent Activity
- [ ] List recent conversations across all councils
- [ ] "Continue conversation" quick action
- [ ] Last activity timestamp
- [ ] Unread/new message indicators

#### 2. Quick Actions Widget
- [ ] "Start new conversation" (with recent councils dropdown)
- [ ] "Create new council" button
- [ ] "Switch space" shortcut
- [ ] "Add provider" if none configured

#### 3. Activity Feed
- [ ] Timeline of recent events:
  - New councils created
  - Conversations started/resolved
  - Advisors added
  - AI responses received
- [ ] Filter by type
- [ ] Real-time updates (Turbo Streams)

#### 4. Empty State Improvements
- [ ] Better onboarding for new users
- [ ] Guided setup wizard (optional)
- [ ] Example/template councils
- [ ] Help/tooltip system

---

## Technical Debt & Polish

- [ ] Performance: Conversation pagination, message lazy loading
- [ ] Error handling: Retry logic, graceful degradation
- [ ] Background job monitoring (Solid Queue UI)

---

## Priority Order

1. ✅ ~~**Critical Security Fixes**~~ - All completed
2. ✅ ~~**Phase 3 (Meeting Lifecycle)**~~ - Core implementation complete
3. **Phase 4 (Usage Dashboard)** - Critical for production/billing
4. **Dashboard Enhancements** - Nice UX improvements
5. **Documentation** - Keep docs in sync with code
6. **Technical Debt** - As needed based on usage

---

## Recently Completed

- ✅ Multi-tenancy with acts_as_tenant
- ✅ Spaces, Councils, Advisors, Providers
- ✅ AI Integration (OpenAI, Anthropic)
- ✅ Rules of Engagement (5 modes)
- ✅ Security audit & hardening (417+ tests)
- ✅ Conversation Lifecycle & RoE refactoring
- ✅ Conversation auto-conclusion based on RoE

---

Last updated: 2026-02-18
