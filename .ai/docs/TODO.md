# TODO

## Security & Correctness Audit Follow-ups



## Remaining Features to Implement

### Phase 3: Meeting Lifecycle

#### 1. Conversation Resolution
- [ ] Add `status` enum to conversations (active, resolved)
- [ ] "Resolve/End Conversation" button in conversation UI
- [ ] Confirmation dialog with memory generation options
- [ ] Resolved conversations become read-only (no new messages)
- [ ] Visual indicator (badge/icon) for resolved conversations

#### 2. AI Memory Generation
- [ ] On conversation resolution, trigger background job
- [ ] AI analyzes full conversation transcript
- [ ] Generates structured summary with:
  - Key decisions made
  - Action items identified
  - Important insights
  - Open questions
- [ ] Store generated memory in conversation.memory

#### 3. User Review & Edit
- [ ] Display AI-generated memory to user for review
- [ ] Rich text editor for editing/saving changes
- [ ] Accept/Reject options
- [ ] Option to regenerate with different focus

#### 4. Persist to Space Memory
- [ ] Save approved memory to `space.memory` (cumulative knowledge)
- [ ] Link back to source conversation
- [ ] Deduplication/similarity detection for repeated insights
- [ ] Memory browser/search in space view

---

### Usage Dashboard

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

### Dashboard Enhancements

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

1. **Critical Security Fixes** - Tenant-unsafe login lookup
2. **High Security Fixes** - Space authorization, provider admin roles
3. **Phase 3 (Meeting Lifecycle)** - Completes core user loop
4. **Usage Dashboard** - Critical for production/billing
5. **Dashboard Enhancements** - Nice UX improvements
6. **Documentation** - Keep docs in sync with code
7. **Technical Debt** - As needed based on usage

---

Last updated: 2026-02-18
