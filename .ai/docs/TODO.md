# TODO

## Security & Correctness Audit Follow-ups

### Critical

- [x] Fix tenant-unsafe login lookup in `app/controllers/sessions_controller.rb` (use tenant-aware sign-in flow; avoid global `User.find_by(email: ...)` ambiguity). **FIXED**: 
  - Enforced global email uniqueness in User model (`validates :email, uniqueness: true`)
  - Added database unique index on `users.email` (migration: `ChangeUserEmailIndexToGlobal`)
  - Removed scoped index on `[account_id, email]`
  - SessionsController lookup now finds user globally; tenant established via `user.account`

### High

- [ ] Enforce space authorization in `app/controllers/messages_controller.rb` so users cannot post to conversations outside `Current.space`.
- [ ] Add role-based authorization for provider management in `app/controllers/providers_controller.rb` (restrict create/update/destroy to admins).

### Medium

- [ ] Prevent email enumeration in `app/controllers/identity/password_resets_controller.rb` by returning a generic response for both existing and non-existing emails.
- [ ] Align provider immutability behavior: either remove `provider_type` from update params or allow/communicate changes consistently (`app/controllers/providers_controller.rb`, `app/views/providers/edit.html.erb`).
- [ ] Harden `GenerateAdvisorResponseJob` by verifying advisor/conversation/message belong to the same account/conversation before updating records.

### Low

- [ ] Implement account deactivation access blocking (currently skipped in `test/controllers/security_controller_test.rb`).

---

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

## Documentation Status (Updated 2026-02-18)

- [x] Replace template `README.md` with real setup/run/deploy instructions. (Deferred - not critical for internal)
- [x] Update `.ai/docs/overview.md` - Refreshed with current stack, Hotwire active, acts_as_tenant enabled
- [x] Update `.ai/docs/features/multi-tenancy.md` - Updated to reflect active tenant setup
- [x] Add missing feature docs:
  - [x] Spaces - New doc for workspace organization
  - [x] Councils - New doc for advisor groups
  - [x] Advisors - New doc for AI personas
  - [x] Providers - New doc for AI credentials
- [x] Expand `.ai/docs/patterns/architecture.md` - Added tenant context, AI orchestration, jobs/streams
- [x] Update feature and pattern indexes

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
