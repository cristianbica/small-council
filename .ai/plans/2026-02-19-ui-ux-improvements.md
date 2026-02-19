# UI/UX Improvements Plan for Small Council

Date: 2026-02-19

## Goal

Comprehensive UI/UX improvements across all major views of the Small Council Rails application to create a polished, professional, and accessible user experience.

## Current State Analysis

### What's Working Well
- **Layout** (`application.html.erb`): Good foundation with DaisyUI theme, flash messages with icons, responsive container
- **Auth views** (`sessions/new.html.erb`, `registrations/new.html.erb`): Clean card-based forms with proper DaisyUI structure
- **Navigation** (`_navigation.html.erb`): Has navbar with space switcher, mobile nav, user dropdown
- **Forms** (`_form.html.erb` files): Generally good structure with DaisyUI classes

### Areas Needing Improvement

| View | Current State | Priority |
|------|--------------|----------|
| `home/index.html.erb` | Very basic HTML, no styling, needs complete redesign | High |
| **Forms (all)** | Inconsistent error display, no field-level validation, missing required indicators, poor checkbox styling | **Critical** |
| `dashboard/index.html.erb` | Decent card layout but visual hierarchy could be improved | Medium |
| `conversations/show.html.erb` | Chat interface works but needs polish (message bubbles, input UX) | High |
| `messages/_message.html.erb` | Basic chat bubbles, could use refinement | Medium |
| `councils/index.html.erb` | Card grid okay but empty states could be better | Low |
| `providers/index.html.erb` | Needs visual polish and better status indicators | Medium |
| `spaces/memory.html.erb` | Needs better content hierarchy and empty states | Medium |
| `spaces/search_memory.html.erb` | Needs better results presentation | Low |
| `conversations/_summary_review.html.erb` | Form layout could be improved | Medium |

---

## Scope

### In Scope
1. **CRITICAL: Fix all forms** - Consistent validation UX, field-level errors, required indicators, improved checkbox styling
2. Redesign `home/index.html.erb` as a proper account/settings page
3. Improve visual hierarchy across all views
4. Add consistent empty states with helpful CTAs
5. Polish conversation/chat interface
6. Improve navigation UX (active states, better mobile experience)
7. Add loading states where appropriate
8. Ensure consistent spacing and typography

### Out of Scope
- No new features or functionality
- No changes to backend logic
- No JavaScript-heavy interactions (keep server-rendered)
- No custom CSS outside Tailwind/DaisyUI
- No changes to authentication flow

---

## Standards & Patterns

### UI Standards
- Use Tailwind utility classes and DaisyUI components exclusively
- Keep server-rendered Rails patterns (no unnecessary JS)
- Ensure accessibility (semantic HTML, labels, focus states, ARIA where needed)
- Responsive design (mobile, tablet, desktop)
- Consistent empty states, loading states, error states
- Progressive enhancement over JS-heavy interactions

### DaisyUI Components to Leverage
- `card` - Content containers
- `btn`, `btn-primary`, `btn-ghost` - Action buttons
- `badge` - Status indicators
- `alert` - Flash messages and status
- `form-control`, `input`, `textarea` - Form elements
- `dropdown` - Navigation and actions
- `tabs` - Content organization
- `divider` - Visual separation
- `skeleton` - Loading states
- `stat` - Dashboard metrics
- `timeline` - Activity/history display
- `hero` - Landing/empty states

### Spacing & Typography Patterns
- Page headers: `text-3xl font-bold` with `text-base-content/70` subtitle
- Section cards: `card bg-base-100 shadow` with `card-body`
- Consistent vertical rhythm: `space-y-6` between major sections
- Form labels: `label` with `label-text`
- Helper text: `text-sm text-base-content/60`

---

## Implementation Steps

### Phase 1: Form UX Overhaul (CRITICAL) (Files: 10)

#### Step 1.1: Create Form Field Partial with Validation
**File:** `app/views/shared/_form_field.html.erb` (new)

Create reusable form field component with consistent validation UX:
```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">
      <%= label %>
      <% if required %>
        <span class="text-error" aria-label="required">*</span>
      <% end %>
    </span>
    <% if hint %>
      <span class="label-text-alt text-base-content/60"><%= hint %></span>
    <% end %>
  </label>
  
  <%= yield %>
  
  <% if errors.any? %>
    <label class="label">
      <span class="label-text-alt text-error flex items-center gap-1">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <%= errors.first %>
      </span>
    </label>
  <% end %>
</div>
```

#### Step 1.2: Fix Provider Forms
**Files:** 
- `app/views/providers/new.html.erb`
- `app/views/providers/edit.html.erb`

Changes:
- Add field-level error indicators (red border on invalid fields)
- Add required field markers (*)
- Fix checkbox styling with proper label alignment
- Consistent error alert with icon
- Helper text for all complex fields

Example pattern:
```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">
      Name
      <span class="text-error">*</span>
    </span>
  </label>
  <%= form.text_field :name, 
      class: "input input-bordered #{'input-error' if form.object.errors[:name].any?}",
      required: true,
      placeholder: "e.g., OpenAI Production" %>
  <% if form.object.errors[:name].any? %>
    <label class="label">
      <span class="label-text-alt text-error"><%= form.object.errors[:name].first %></span>
    </label>
  <% end %>
</div>

<!-- Better checkbox styling -->
<div class="form-control">
  <label class="label cursor-pointer justify-start gap-3">
    <%= form.check_box :enabled, class: "checkbox checkbox-primary" %>
    <span class="label-text">Enabled</span>
  </label>
</div>
```

#### Step 1.3: Fix Council Forms
**Files:**
- `app/views/councils/_form.html.erb`
- `app/views/councils/new.html.erb`
- `app/views/councils/edit.html.erb`

Changes:
- Apply consistent form field patterns
- Field-level validation feedback
- Required field indicators
- Improved textarea sizing

#### Step 1.4: Fix Advisor Forms
**File:** `app/views/advisors/_form.html.erb`

Changes:
- Consistent error display
- Required markers for name and model
- Better select dropdown styling
- Improved prompt textarea with character count

#### Step 1.5: Fix Space Forms
**File:** `app/views/spaces/_form.html.erb`

Changes:
- Apply consistent validation patterns
- Required field indicators
- Better placeholder text

#### Step 1.6: Fix Conversation Forms
**Files:**
- `app/views/conversations/new.html.erb`
- `app/views/conversations/_summary_review.html.erb`

Changes:
- Consistent form structure
- Field-level errors
- Better textarea styling for summary review
- Collapsible raw summary section

---

### Phase 2: Foundation & Navigation (Files: 2)

#### Step 2.1: Improve Navigation UX
**File:** `app/views/layouts/_navigation.html.erb`

Changes:
- Add active state indicators for current page
- Improve mobile navigation with labels
- Add tooltips or aria-labels for icon-only buttons
- Ensure consistent spacing in navbar

```erb
<!-- Add active state styling -->
<li><%= link_to "Dashboard", dashboard_path, class: "#{current_page?(dashboard_path) ? 'active' : ''}" %></li>
```

#### Step 2.2: Create Shared Empty State Partial
**File:** `app/views/shared/_empty_state.html.erb` (new)

Create reusable empty state component:
```erb
<div class="hero bg-base-200 rounded-lg py-12">
  <div class="hero-content text-center">
    <div>
      <% if local_assigns[:icon] %>
        <div class="mb-4"><%= icon %></div>
      <% end %>
      <h3 class="text-xl font-bold mb-2"><%= title %></h3>
      <p class="text-base-content/60 mb-4"><%= description %></p>
      <% if local_assigns[:action_path] %>
        <%= link_to action_text, action_path, class: "btn btn-primary" %>
      <% end %>
    </div>
  </div>
</div>
```

---

### Phase 3: Home/Account Page Redesign (Files: 1)

#### Step 2.1: Redesign Home Index
**File:** `app/views/home/index.html.erb`

Transform from basic HTML to a proper account management page:

Structure:
- Page header with user greeting
- Account settings section (password, email)
- Security section (sessions/devices)
- Logout action in danger zone

```erb
<div class="space-y-6">
  <!-- Header -->
  <div>
    <h1 class="text-3xl font-bold">Account Settings</h1>
    <p class="text-base-content/70 mt-1">
      Signed in as <span class="font-medium"><%= Current.user.email %></span>
    </p>
  </div>

  <!-- Account Settings Card -->
  <div class="card bg-base-100 shadow">
    <div class="card-body">
      <h2 class="card-title mb-4">
        <svg class="w-5 h-5"...></svg>
        Login & Verification
      </h2>
      <div class="space-y-3">
        <%= link_to edit_password_path, class: "flex items-center justify-between p-3 bg-base-200 rounded-lg hover:bg-base-300 transition-colors" do %>
          <div>
            <p class="font-medium">Change Password</p>
            <p class="text-sm text-base-content/60">Update your account password</p>
          </div>
          <svg class="w-5 h-5 text-base-content/40">...</svg>
        <% end %>
        <%= link_to edit_identity_email_path, class: "flex items-center justify-between p-3 bg-base-200 rounded-lg hover:bg-base-300 transition-colors" do %>
          <div>
            <p class="font-medium">Change Email Address</p>
            <p class="text-sm text-base-content/60">Update your email and verify</p>
          </div>
          <svg class="w-5 h-5 text-base-content/40">...</svg>
        <% end %>
      </div>
    </div>
  </div>

  <!-- Security Card -->
  <div class="card bg-base-100 shadow">
    <div class="card-body">
      <h2 class="card-title mb-4">
        <svg class="w-5 h-5"...></svg>
        Security
      </h2>
      <%= link_to sessions_path, class: "flex items-center justify-between p-3 bg-base-200 rounded-lg hover:bg-base-300 transition-colors" do %>
        <div>
          <p class="font-medium">Devices & Sessions</p>
          <p class="text-sm text-base-content/60">Manage active sessions and sign out remotely</p>
        </div>
        <svg class="w-5 h-5 text-base-content/40">...</svg>
      <% end %>
    </div>
  </div>

  <!-- Danger Zone -->
  <div class="card bg-base-100 shadow border-error/20">
    <div class="card-body">
      <h2 class="card-title text-error mb-4">
        <svg class="w-5 h-5"...></svg>
        Danger Zone
      </h2>
      <%= button_to session_path(Current.session), method: :delete, 
          class: "btn btn-error btn-outline" do %>
        <svg class="w-4 h-4 mr-2">...</svg>
        Sign Out
      <% end %>
    </div>
  </div>
</div>
```

---

### Phase 4: Dashboard Improvements (Files: 1)

#### Step 3.1: Enhanced Dashboard Layout
**File:** `app/views/dashboard/index.html.erb`

Changes:
- Add stats/overview cards at top
- Improve council cards with better metadata
- Add "View All" links for truncated lists
- Better empty states using shared partial

```erb
<!-- Add stats row -->
<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
  <div class="stat bg-base-100 shadow rounded-lg">
    <div class="stat-title">Councils</div>
    <div class="stat-value"><%= @councils.count %></div>
    <div class="stat-desc">Active councils</div>
  </div>
  <div class="stat bg-base-100 shadow rounded-lg">
    <div class="stat-title">Conversations</div>
    <div class="stat-value"><%= @conversations.count %></div>
    <div class="stat-desc">Total conversations</div>
  </div>
  <div class="stat bg-base-100 shadow rounded-lg">
    <div class="stat-title">Space</div>
    <div class="stat-value text-lg"><%= Current.space.name %></div>
    <div class="stat-desc"><%= link_to "Switch", spaces_path, class: "link link-primary" %></div>
  </div>
</div>
```

---

### Phase 5: Conversation Interface Polish (Files: 3)

#### Step 4.1: Enhanced Message Bubbles
**File:** `app/views/messages/_message.html.erb`

Changes:
- Better avatar/identifier display
- Improved timestamp formatting
- Better pending/error state visuals
- Add copy button for messages

```erb
<div class="flex <%= is_current_user ? 'justify-end' : 'justify-start' %> gap-3">
  <% unless is_current_user %>
    <div class="avatar placeholder">
      <div class="bg-neutral text-neutral-content rounded-full w-8 h-8">
        <span class="text-xs"><%= message.sender.name.first.upcase %></span>
      </div>
    </div>
  <% end %>
  
  <div class="max-w-[75%]">
    <div class="flex items-baseline gap-2 mb-1 <%= is_current_user ? 'justify-end' : '' %>">
      <span class="text-sm font-medium"><%= message.sender.name %></span>
      <span class="text-xs text-base-content/50"><%= time_ago_in_words(message.created_at) %> ago</span>
      <% if is_pending %>
        <span class="loading loading-spinner loading-xs"></span>
      <% end %>
    </div>
    
    <div class="<%= bubble_classes %> rounded-2xl px-4 py-2 shadow-sm">
      <div class="whitespace-pre-wrap"><%= message.content %></div>
    </div>
  </div>
</div>
```

#### Step 4.2: Improved Conversation Show Page
**File:** `app/views/conversations/show.html.erb`

Changes:
- Sticky header with conversation info
- Better message input area (fixed at bottom)
- Improved status badges
- Better RoE dropdown styling
- Add participants list

Key improvements:
```erb
<!-- Sticky message input -->
<section class="card bg-base-100 shadow sticky bottom-4">
  <div class="card-body py-3">
    <%= form_with model: [@conversation, @new_message], 
        class: "flex items-end gap-2" do |form| %>
      <div class="form-control flex-1">
        <%= form.text_area :content,
            class: "textarea textarea-bordered w-full resize-none",
            placeholder: "Type your message...",
            rows: 1,
            required: true,
            data: { controller: "textarea-autogrow" } %>
      </div>
      <%= form.button type: :submit, class: "btn btn-primary btn-circle" do %>
        <svg class="w-5 h-5">...</svg>
      <% end %>
    <% end %>
  </div>
</section>
```

#### Step 4.3: Summary Review Improvements
**File:** `app/views/conversations/_summary_review.html.erb`

Changes:
- Better visual hierarchy for form sections
- Collapsible raw summary section
- Improved action button layout
- Add preview/help text for each field

---

### Phase 6: Council & Space Views (Files: 4)

#### Step 5.1: Enhanced Council Index
**File:** `app/views/councils/index.html.erb`

Changes:
- Add council count badge in header
- Better card layout with hover effects
- Improved advisor count display
- Use shared empty state partial

#### Step 5.2: Council Show Page Improvements
**File:** `app/views/councils/show.html.erb`

Changes:
- Better advisor cards with role/prompt preview
- Tabbed interface for Advisors vs Conversations
- Improved conversation list with status indicators

#### Step 5.3: Memory Page Improvements
**File:** `app/views/spaces/memory.html.erb`

Changes:
- Better search interface with icon
- Improved memory display with formatting
- Better conversation history cards
- Empty state for no memories

#### Step 5.4: Search Results Improvements
**File:** `app/views/spaces/search_memory.html.erb`

Changes:
- Highlight search matches better
- Add result count badge
- Better "no results" state
- Keep search term in input

---

### Phase 7: Provider & Other Improvements (Files: 2)

#### Step 7.1: Provider Index Polish
**File:** `app/views/providers/index.html.erb`

Changes:
- Status badges with icons (use `badge-success`/`badge-error` for enabled/disabled)
- Better model display as tags/badges
- Connection status indicator
- Improved empty state using shared partial

#### Step 7.2: Conversations Index Improvements
**File:** `app/views/conversations/index.html.erb`

Changes:
- Better list layout with avatar indicators
- Status badges with colors
- Last activity timestamp
- Improved empty state using shared partial

---

## Affected Files

### Views to Modify (18 files)
1. `app/views/home/index.html.erb` - Complete redesign
2. `app/views/dashboard/index.html.erb` - Enhanced layout
3. `app/views/conversations/show.html.erb` - Chat interface polish
4. `app/views/conversations/index.html.erb` - List improvements
5. `app/views/conversations/_summary_review.html.erb` - Form layout
6. `app/views/conversations/new.html.erb` - Form improvements
7. `app/views/messages/_message.html.erb` - Message bubbles
8. `app/views/councils/index.html.erb` - Card improvements
9. `app/views/councils/show.html.erb` - Tabbed interface
10. `app/views/councils/_form.html.erb` - Form validation UX
11. `app/views/councils/new.html.erb` - Form layout
12. `app/views/councils/edit.html.erb` - Form layout
13. `app/views/spaces/memory.html.erb` - Content hierarchy
14. `app/views/spaces/search_memory.html.erb` - Results display
15. `app/views/spaces/_form.html.erb` - Form validation UX
16. `app/views/providers/index.html.erb` - Status indicators
17. `app/views/providers/new.html.erb` - Form validation UX
18. `app/views/providers/edit.html.erb` - Form validation UX
19. `app/views/advisors/_form.html.erb` - Form validation UX
20. `app/views/layouts/_navigation.html.erb` - Active states

### New Files (2 files)
1. `app/views/shared/_empty_state.html.erb` - Reusable empty state component
2. `app/views/shared/_form_field.html.erb` - Reusable form field with validation

---

## UI Patterns Reference

### Empty State Pattern
```erb
<%= render "shared/empty_state",
    icon: hero_icon("users", class: "w-16 h-16"),
    title: "No councils yet",
    description: "Create your first council to start collaborating with AI advisors.",
    action_path: new_council_path,
    action_text: "Create Council" %>
```

### Card with Header Pattern
```erb
<div class="card bg-base-100 shadow">
  <div class="card-body">
    <div class="flex items-center justify-between mb-4">
      <h2 class="card-title">Section Title</h2>
      <span class="badge badge-primary">3</span>
    </div>
    <!-- Content -->
  </div>
</div>
```

### Form Field with Error Pattern
```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">Field Label <span class="text-error">*</span></span>
  </label>
  <%= form.text_field :field, class: "input input-bordered #{'input-error' if errors?}" %>
  <% if errors? %>
    <label class="label">
      <span class="label-text-alt text-error">Error message</span>
    </label>
  <% end %>
</div>
```

### Status Badge Pattern
```erb
<span class="badge <%= status_badge_class(object) %> badge-sm">
  <%= object.status %>
</span>

<!-- Helper method -->
def status_badge_class(conversation)
  case conversation.status
  when "active" then "badge-success"
  when "concluding" then "badge-warning"
  when "resolved" then "badge-ghost"
  else "badge-ghost"
  end
end
```

---

## Acceptance Criteria

### General
- [ ] All views use consistent DaisyUI components
- [ ] All views are responsive (mobile, tablet, desktop)
- [ ] All interactive elements have visible focus states
- [ ] All forms have proper labels and error handling
- [ ] All empty states use the shared partial

### Home/Account Page
- [ ] Page has professional card-based layout
- [ ] Settings are organized into logical sections
- [ ] Each setting has clear description
- [ ] Sign out is in danger zone styling

### Dashboard
- [ ] Stats cards show at top
- [ ] Council cards have consistent hover effects
- [ ] Empty states have helpful CTAs

### Conversations
- [ ] Message bubbles have clear sender identification
- [ ] Input area is sticky/fixed at bottom
- [ ] Status changes are visually clear
- [ ] RoE dropdown is properly styled

### Navigation
- [ ] Current page is highlighted in nav
- [ ] Mobile nav has clear labels
- [ ] User dropdown shows relevant info

### Forms (Critical)
- [ ] All required fields marked with red asterisk (*)
- [ ] Field-level errors show inline with red text and error icon
- [ ] Invalid fields have red border (`input-error` class)
- [ ] Error alerts at top of form have consistent styling with icon
- [ ] Helper text is present for all complex fields
- [ ] Checkboxes use consistent `label cursor-pointer justify-start gap-3` pattern
- [ ] All forms have consistent spacing (`space-y-4`)
- [ ] Submit buttons are clearly primary actions (`btn-primary`)
- [ ] Cancel buttons use `btn-ghost` consistently
- [ ] Focus states are clearly visible on all inputs

---

## Verification Steps

1. **Responsive Testing**
   ```bash
   # Start server
   bin/dev
   
   # Test at different viewports
   # - Mobile: 375px
   # - Tablet: 768px
   # - Desktop: 1280px
   ```

2. **Accessibility Testing**
   - Verify all form inputs have labels
   - Check focus indicators are visible
   - Test keyboard navigation
   - Run axe-core or similar tool

3. **Visual Regression**
   - Compare before/after screenshots
   - Check consistency across all views
   - Verify DaisyUI theme applies correctly

4. **Form Testing (Critical)**
   - Submit each form with empty required fields
   - Verify field-level error messages appear
   - Check error borders show on invalid fields
   - Test keyboard navigation through forms
   - Verify required field markers (*) are visible
   - Test checkbox styling and interaction

5. **Functionality Testing**
   - Submit forms with errors
   - Test empty states
   - Verify navigation active states
   - Test mobile navigation

---

## Doc Impact

- **Create:** `.ai/docs/patterns/ui-components.md` - Document reusable UI patterns
- **Update:** `.ai/MEMORY.md` - Add UI/UX standards section
- **Update:** `.ai/docs/features/ui-framework.md` - Add component usage examples

---

## Rollback Plan

If issues arise:
1. Revert individual view files using git
2. Keep `shared/_empty_state.html.erb` and `shared/_form_field.html.erb` as they won't break existing code
3. Navigation changes can be reverted independently
4. Form changes are localized and can be reverted per-form

---

## Timeline Estimate

| Phase | Files | Estimated Time |
|-------|-------|----------------|
| Phase 1: Form UX Overhaul (CRITICAL) | 10 | 3 hours |
| Phase 2: Foundation & Navigation | 2 | 1 hour |
| Phase 3: Home Page | 1 | 1.5 hours |
| Phase 4: Dashboard | 1 | 1 hour |
| Phase 5: Conversations | 3 | 2.5 hours |
| Phase 6: Councils & Spaces | 4 | 2 hours |
| Phase 7: Provider & Other | 2 | 1 hour |
| Testing & Polish | - | 2 hours |
| **Total** | **23** | **~14 hours** |

---

## Notes

- Keep changes localized to views only
- No backend changes required
- Test with both light and dark themes if applicable
- Ensure Turbo Drive compatibility (no full page reload issues)
- Consider adding Stimulus controllers only if absolutely necessary for UX

## Form Issues Being Fixed

Based on review of current forms, these specific issues will be addressed:

1. **Inconsistent error display** - Some forms have error icons, some don't
2. **No field-level error indicators** - Users can't see which field has errors
3. **Missing required field markers** - No visual indication of required fields
4. **Inconsistent spacing** - Some use `space-y-4`, others don't
5. **Poor checkbox styling** - Checkboxes look out of place, not aligned with labels
6. **No focus state feedback** - No visual indication of active fields
7. **Inconsistent error alert styling** - Some alerts lack icons or consistent structure
8. **Missing helper text** - Complex fields lack explanation
