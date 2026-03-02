# Plan: Chat UI Refactor (Light Theme, DaisyUI-first)

**Date:** 2026-03-02  
**Status:** Draft - awaiting approval

---

## Goal
Transform the chat UI into a modern, clean interface using **DaisyUI primitives** and **Tailwind utilities** with a **light theme**. The layout must have fixed header, scrollable message area, and fixed input. Implementation is **staged** with Playwright verification at each checkpoint.

---

## Constraints
- **Theme:** Light (DaisyUI default/light theme)
- **Sidebar:** Remains visible in conversations view
- **Stack:** Tailwind CSS v4 + DaisyUI v5 + Stimulus (no custom CSS frameworks)
- **Scope:** Chat UI surface only (messages list, message bubbles, composer, scroll behavior)
- **Excluded:** Global navigation, sidebar styling, participants panel, breadcrumbs

---

## Reference Analysis (tmp/chat-demo.html)

**Key patterns to adapt for light theme:**

1. **Layout structure:**
   - Fixed header at top
   - Scrollable message area (flex: 1, overflow-y: auto)
   - Fixed input at bottom
   - Only messages scroll

2. **DaisyUI chat components:**
   - `.chat`, `.chat-start` (AI/others), `.chat-end` (current user)
   - `.chat-image.avatar` for sender avatars
   - `.chat-header` for name + timestamp
   - `.chat-bubble` for message content
   - `.chat-footer` for actions/status

3. **Spacing & sizing:**
   - Container: max-w-3xl (768px) centered
   - Message gap: space-y-6 (24px)
   - Padding: py-8 px-6 (messages area)
   - Bubbles: px-4 py-3

4. **Visual hierarchy (light theme):**
   - AI bubbles: subtle neutral background (bg-base-200)
   - User bubbles: primary-tinted background (bg-primary/10)
   - Avatars: consistent sizing (w-10 h-10)
   - Actions: opacity-0 → opacity-100 on group-hover

5. **Composer:**
   - Rounded container (rounded-2xl)
   - Textarea with transparent bg
   - Action buttons (attach, send)
   - Helper text below

---

## Stage 1: Layout Foundation (HEADER + MESSAGES + INPUT structure)

### Files to modify:
1. `app/views/layouts/conversation.html.erb` - overall layout structure
2. `app/views/conversations/show.html.erb` - conversation view
3. `app/views/councils/show.html.erb` - council meeting view (full-width)
4. `app/views/shared/_chat.html.erb` - new shared chat container

### Changes:

#### A. Layout wrapper (`app/views/layouts/conversation.html.erb`)
```erb
<!-- Structure: h-screen flex flex-col -->
<!-- Header: flex-none -->
<!-- Main: flex-1 flex overflow-hidden -->
  <!-- Sidebar (conversations only): w-80 flex-none -->
  <!-- Chat area: flex-1 flex flex-col min-w-0 -->
    <!-- Chat header: flex-none -->
    <!-- Messages: flex-1 overflow-y-auto -->
    <!-- Input: flex-none -->
```

#### B. Conversation view (`app/views/conversations/show.html.erb`)
- Remove breadcrumbs
- Use two-column layout: sidebar + chat
- Sidebar: conversation list using DaisyUI menu
- Chat: render shared/_chat partial

#### C. Council meeting view (`app/views/councils/show.html.erb`)
- Full-width chat (no sidebar)
- Same chat partial

#### D. Shared chat partial (`app/views/shared/_chat.html.erb`) - NEW
```erb
<div class="chat-main flex flex-col h-full">
  <!-- Fixed header -->
  <header class="flex-none px-6 py-4 border-b border-base-200">
    <!-- Conversation title, status badges, actions -->
  </header>
  
  <!-- Scrollable messages -->
  <div class="messages-area flex-1 overflow-y-auto py-8 px-6" data-controller="conversation">
    <div class="max-w-3xl mx-auto space-y-6">
      <%= render partial: "messages/message_thread", collection: @messages, as: :message %>
    </div>
  </div>
  
  <!-- Fixed input -->
  <div class="input-area flex-none px-6 py-4 border-t border-base-200 bg-base-100">
    <!-- Composer -->
  </div>
</div>
```

### CSS needed (minimal):
```css
/* Only for custom scrollbar and smooth scroll */
.messages-area {
  scroll-behavior: smooth;
}
.messages-area::-webkit-scrollbar {
  width: 6px;
}
.messages-area::-webkit-scrollbar-track {
  background: transparent;
}
.messages-area::-webkit-scrollbar-thumb {
  background: var(--color-base-300);
  border-radius: 999px;
}
```

### Verification (Stage 1 checkpoint):
- [ ] Screenshot shows header fixed at top
- [ ] Screenshot shows message area scrollable
- [ ] Screenshot shows input fixed at bottom
- [ ] No page-level scroll, only messages scroll

---

## Stage 2: Message Structure (DaisyUI chat components)

### Files to modify:
1. `app/views/messages/_message_thread.html.erb` - threaded messages
2. `app/views/messages/_message.html.erb` - single message (if used standalone)

### Changes:

#### A. Message partial rewrite
```erb
<%# Determine alignment %>
<% is_current_user = message.sender == current_user %>
<% is_advisor = message.advisor? %>
<% alignment = is_current_user ? 'chat-end' : 'chat-start' %>
<% bubble_class = is_current_user ? 'bg-primary text-primary-content' : 'bg-base-200 text-base-content' %>

<div class="chat <%= alignment %>" id="message_<%= message.id %>">
  <!-- Avatar -->
  <div class="chat-image avatar">
    <div class="w-10 h-10 rounded-full flex items-center justify-center <%= is_advisor ? 'bg-primary text-primary-content' : 'bg-neutral text-neutral-content' %>">
      <% if is_advisor %>
        <%= message.sender.name.first.upcase %>
      <% else %>
        <%= message.sender.name.first.upcase %>
      <% end %>
    </div>
  </div>
  
  <!-- Header (name + time) -->
  <div class="chat-header">
    <%= message.sender.name %>
    <time class="text-xs opacity-60 ml-2"><%= time_ago_in_words(message.created_at) %> ago</time>
    <% if message.pending? %>
      <span class="loading loading-spinner loading-xs ml-2"></span>
    <% end %>
  </div>
  
  <!-- Bubble -->
  <div class="chat-bubble <%= bubble_class %> max-w-[85%] sm:max-w-[75%] whitespace-pre-wrap">
    <%= message.content %>
  </div>
  
  <!-- Footer with actions -->
  <div class="chat-footer opacity-0 group-hover:opacity-100 transition-opacity">
    <button class="btn btn-ghost btn-xs" title="Copy">Copy</button>
    <% if is_advisor %>
      <button class="btn btn-ghost btn-xs" title="Good">👍</button>
      <button class="btn btn-ghost btn-xs" title="Bad">👎</button>
      <button class="btn btn-ghost btn-xs" title="Regenerate">🔄</button>
    <% end %>
  </div>
</div>
```

#### B. Threaded layout
- Keep `.message-thread` wrapper for indentation
- Apply margin-left for replies: `ml-8 sm:ml-12`
- Use same chat component structure inside

### Verification (Stage 2 checkpoint):
- [ ] Screenshot shows AI messages on left (chat-start)
- [ ] Screenshot shows user messages on right (chat-end)
- [ ] Avatars visible and aligned
- [ ] Bubbles have distinct styling (neutral vs primary-tinted)
- [ ] Timestamps visible
- [ ] Layout matches reference structure

---

## Stage 3: Polish & Interactions

### Files to modify:
1. `app/javascript/controllers/conversation_controller.js` - scroll behavior
2. `app/assets/stylesheets/application.css` - hover action transitions
3. `app/views/shared/_chat.html.erb` - composer styling

### Changes:

#### A. Scroll behavior (Stimulus)
```javascript
// conversation_controller.js
// - Track scroll position
// - Auto-scroll to bottom on new messages (if already at bottom)
// - Show "scroll to latest" button when not at bottom
// - Smooth scroll behavior
```

#### B. Hover actions (CSS)
```css
/* app/assets/stylesheets/application.css */
.chat {
  position: relative;
}
.chat:hover .chat-footer {
  opacity: 1;
}
.chat-footer {
  opacity: 0;
  transition: opacity 0.2s ease;
}
```

#### C. Composer styling
```erb
<!-- Input area -->
<div class="input-area flex-none px-6 py-4 border-t border-base-200 bg-base-100">
  <div class="max-w-3xl mx-auto">
    <div class="join w-full">
      <textarea 
        class="textarea textarea-bordered join-item flex-1 min-h-[80px] resize-none" 
        placeholder="Type your message... (Ctrl+Enter to send, @ to mention)"></textarea>
      <button class="btn btn-primary join-item">
        <svg><!-- send icon --></svg>
      </button>
    </div>
    <div class="mt-2 flex justify-between text-xs text-base-content/60">
      <div>
        Use <kbd class="kbd kbd-sm">@all</kbd> for everyone
        <kbd class="kbd kbd-sm">/invite @advisor</kbd> to add
      </div>
      <div>0 / 4000</div>
    </div>
  </div>
</div>
```

### Verification (Stage 3 checkpoint):
- [ ] Hover actions appear on message hover
- [ ] Scroll-to-latest button works
- [ ] Composer has proper styling
- [ ] Input hint text visible
- [ ] Character count displayed
- [ ] Overall look matches modern chat UI expectations

---

## Implementation Order

### Stage 1: Layout Foundation
1. Create `app/views/shared/_chat.html.erb` with flex structure
2. Update `app/views/conversations/show.html.erb` to use sidebar + chat layout
3. Update `app/views/councils/show.html.erb` for full-width chat
4. Adjust `app/views/layouts/conversation.html.erb` for proper flex structure
5. **VERIFICATION:** Playwright screenshot → user approval

### Stage 2: Message Structure  
1. Rewrite `app/views/messages/_message_thread.html.erb` with DaisyUI chat
2. Rewrite `app/views/messages/_message.html.erb` with same pattern
3. Add minimal CSS for scrollbar and hover transitions
4. **VERIFICATION:** Playwright screenshot → user approval

### Stage 3: Polish & Interactions
1. Update `app/javascript/controllers/conversation_controller.js` for scroll behavior
2. Style composer in `app/views/shared/_chat.html.erb`
3. Add hover action CSS
4. **VERIFICATION:** Playwright screenshot → final approval

---

## Acceptance Criteria (Final)

### Layout
- [ ] Header stays fixed at top
- [ ] Messages area is the only scrollable region
- [ ] Input stays fixed at bottom
- [ ] No page-level scroll
- [ ] Works in both conversation (with sidebar) and council meeting (full-width) views

### Messages
- [ ] Uses DaisyUI `.chat` components
- [ ] AI/advisor messages left-aligned (chat-start)
- [ ] User messages right-aligned (chat-end)
- [ ] Avatars visible (w-10 h-10)
- [ ] Names and timestamps displayed
- [ ] Bubbles have distinct backgrounds (neutral for AI, primary-tinted for user)
- [ ] Threaded replies indented (ml-8)

### Interactions
- [ ] Hover actions appear on message hover (desktop)
- [ ] Copy, thumbs up/down, regenerate buttons visible on hover
- [ ] Scroll-to-latest button appears when scrolled up
- [ ] Auto-scroll to bottom when at bottom and new messages arrive

### Composer
- [ ] Rounded container with textarea + send button
- [ ] Helper hints visible (@all, /invite)
- [ ] Character count displayed
- [ ] Keyboard shortcuts work (Ctrl+Enter)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking Turbo Streams | Test live updates after each stage |
| Mobile layout issues | Test responsive breakpoints at each stage |
| Accessibility regression | Verify keyboard navigation, focus states |
| Message threading broken | Keep thread wrapper structure unchanged |

---

## Rollback Plan
- Each stage is independent; can revert individual files
- Keep backup of original partials before each stage
- Git commit between stages for easy reversion

---

**Ready for approval?** I will not proceed until you explicitly approve this plan.