# Plan: Chat UI refactor (messages + composer)

Date: 2026-03-02

## Goal
Implement exact UI patterns from `tmp/chat-demo.html` for the chat interface, ensuring layout, spacing, colors, and interactions match the reference design.

## Non-goals
- Changing conversation/message data models or backend behavior.
- Introducing new JS frameworks or CSS libraries.
- Redesigning global navigation, sidebar, participants, breadcrumbs, or other non-chat elements.

## Scope + assumptions
- Scope: conversation chat views/partials, message partials, Stimulus controllers, and CSS for the chat UI.
- Focus on: messages list layout, message cards/bubbles, metadata (author/time/state), hover actions (copy/thumbs/regenerate), composer, empty/loading states, and scroll-to-latest control.
- Assume DaisyUI chat components remain the base pattern and Turbo Streams continue to deliver live updates.
- Navigation, sidebar, participants, breadcrumbs are explicitly excluded from scope.

---

## Required patterns (from `tmp/chat-demo.html`)

### 1. Layout structure
- **Container**: `flex: 1` column layout with `overflow: hidden` on parent
- **Header**: Fixed at top, `padding: 16px 24px`, border-bottom `oklch(0.22 0.005 260)`
- **Message area**: `flex: 1`, `overflow-y: auto`, `padding: 32px 24px`
- **Input area**: Fixed at bottom, `padding: 16px 24px 24px`, border-top `oklch(0.20 0.005 260)`
- Only `chat-messages` scrolls; header and input remain fixed

### 2. Message container styling
- Max-width: 780px, centered with `margin: 0 auto`
- Gap between messages: 24px (use `display: flex; flex-direction: column; gap: 24px`)
- Messages align to container edges, not full-width

### 3. Message row structure
```html
<div class="msg-row [user]">
  <div class="msg-avatar [ai|human]">A</div>
  <div class="msg-content">
    <div class="msg-name">Name</div>
    <div class="msg-bubble">Content</div>
    <div class="msg-actions">...</div>
    <div class="msg-time">Time</div>
  </div>
</div>
```
- **Avatar**: 34px × 34px, circular, positioned to the left of content
- **User messages**: Add `.user` class → `flex-direction: row-reverse` for right alignment
- **Avatar colors**:
  - AI: `background: oklch(0.65 0.19 250); color: oklch(0.98 0 0)`
  - Human: `background: oklch(0.72 0.16 165); color: oklch(0.13 0.005 260)`

### 4. Message bubbles
- Padding: 14px 18px
- Border-radius: 16px with asymmetrical corners:
  - AI: `border-top-left-radius: 4px` (points to avatar)
  - User: `border-top-right-radius: 4px` (points to avatar)
- Background colors:
  - AI: `oklch(0.18 0.005 260)`
  - User: `oklch(0.25 0.04 250)`
- Text color: `oklch(0.88 0 0)` (AI), `oklch(0.92 0 0)` (User)

### 5. Typography
- **Message content**: 14.5px font-size, 1.6 line-height
- **Sender name (msg-name)**: 13px, font-weight: 600, color `oklch(0.80 0 0)`, margin-bottom: 6px
- **Timestamp (msg-time)**: 11px, color `oklch(0.45 0 0)`, margin-top: 6px
- User messages: Name and timestamp align right (`text-align: right`)

### 6. Hover actions on messages
```html
<div class="msg-actions">
  <button class="msg-action-btn" title="Copy">...</button>
  <button class="msg-action-btn" title="Good response">...</button>
  <button class="msg-action-btn" title="Bad response">...</button>
  <button class="msg-action-btn" title="Regenerate">...</button>
</div>
```
- Container: `display: flex; gap: 2px; margin-top: 8px;`
- Initial state: `opacity: 0`
- Hover state: `opacity: 1` (transition 0.15s ease on `.msg-row:hover .msg-actions`)
- Button sizing: 28px × 28px, border-radius: 8px
- Icons: 14px × 14px
- Desktop only (touch devices: consider tap-to-show or skip)

### 7. Input area styling
```html
<div class="input-wrapper">
  <div class="input-main">
    <textarea rows="1" placeholder="Ask NexusAI anything..."></textarea>
    <div class="input-actions">...</div>
  </div>
  <div class="input-footer">...</div>
</div>
```
- **Wrapper**: max-width: 780px, centered, `background: oklch(0.18 0.005 260)`, border: 1px `oklch(0.26 0.005 260)`, border-radius: 16px
- **Textarea**: transparent bg, no border, placeholder color `oklch(0.45 0 0)`, 14.5px, line-height 1.5, min-height 24px, max-height 160px
- **Focus state**: wrapper border changes to `oklch(0.65 0.19 250)`
- **Icon buttons**: 36px × 36px, border-radius 10px, color `oklch(0.55 0 0)`, hover `background: oklch(0.24 0.005 260)`
- **Send button**: `background: oklch(0.65 0.19 250)`, white icon
- **Footer chips**: 12px font, `background: oklch(0.15 0.005 260)`, border `oklch(0.24 0.005 260)`, border-radius 8px, padding 4px 10px
- **Char count**: 12px, color `oklch(0.40 0 0)`

### 8. Scrollbar styling (thin)
```css
.scrollbar-thin::-webkit-scrollbar {
  width: 6px;
}
.scrollbar-thin::-webkit-scrollbar-track {
  background: transparent;
}
.scrollbar-thin::-webkit-scrollbar-thumb {
  background: oklch(0.30 0.005 260);
  border-radius: 999px;
}
```
- Apply to `.chat-messages` only

### 9. Color palette (oklch)
Use exact oklch values from reference:
- Base background: `oklch(0.13 0.005 260)`
- Card/elevated: `oklch(0.16 0.005 260)`
- Border: `oklch(0.22 0.005 260)`
- AI bubble: `oklch(0.18 0.005 260)`
- User bubble: `oklch(0.25 0.04 250)`
- Primary: `oklch(0.65 0.19 250)`
- Accent: `oklch(0.72 0.16 165)`
- Muted text: `oklch(0.55 0 0)` / `oklch(0.45 0 0)`
- Body text: `oklch(0.92 0 0)` / `oklch(0.88 0 0)`

---

## Steps
1. **Inventory existing chat UI**
   - Map current conversation view, message partials, Stimulus controllers
   - Document gaps between current implementation and reference patterns

2. **Update message layout structure**
   - Restructure chat view: fixed header, flex:1 scrollable messages, fixed input
   - Apply `chat-messages` wrapper with `scrollbar-thin` class
   - Set max-width 780px centered container for message list

3. **Implement message row pattern**
   - Create/extend message partial with `.msg-row` structure
   - Add avatar (34px) + content column layout
   - Apply `.user` class for right-aligned user messages (row-reverse)

4. **Style message bubbles with exact colors**
   - AI bubble: `oklch(0.18 0.005 260)` bg, asymmetrical border-radius
   - User bubble: `oklch(0.25 0.04 250)` bg, asymmetrical border-radius
   - Apply correct text colors and typography (14.5px, 1.6 line-height)

5. **Add typography hierarchy**
   - msg-name: 13px, weight 600, color `oklch(0.80 0 0)`
   - msg-content: 14.5px, line-height 1.6
   - msg-time: 11px, color `oklch(0.45 0 0)`
   - Right-align name/time for user messages

6. **Implement hover actions**
   - Add `.msg-actions` container with 4 buttons (copy, thumbs up, thumbs down, regenerate)
   - CSS: opacity 0 → 1 on row hover, 0.15s transition
   - 28px buttons with hover background `oklch(0.24 0.005 260)`
   - Consider touch fallback (tap-to-show or omit)

7. **Restyle input area**
   - Wrapper: 780px max-width, centered, rounded 16px, border color `oklch(0.26 0.005 260)`
   - Textarea: transparent bg, correct placeholder color
   - Add focus state with primary border color
   - Icon buttons: 36px, 10px radius
   - Footer chips with correct styling

8. **Add scroll-to-latest behavior**
   - Auto-scroll only when user is at bottom
   - Show scroll-to-bottom button when not at bottom
   - Use Stimulus controller for scroll management

9. **Validate responsive behavior**
   - Mobile: adjust padding (16px instead of 24px)
   - Ensure composer stays accessible
   - Test council meeting view with same patterns

---

## Acceptance criteria
- [ ] Layout matches reference: fixed header, flex:1 scrollable messages, fixed input
- [ ] Message container: max-width 780px, centered, 24px gap between messages
- [ ] Message structure: 34px avatar + content column, user messages use row-reverse
- [ ] AI bubble: `oklch(0.18 0.005 260)` bg, 16px radius with `border-top-left-radius: 4px`
- [ ] User bubble: `oklch(0.25 0.04 250)` bg, 16px radius with `border-top-right-radius: 4px`
- [ ] Typography: content 14.5px/1.6, names 13px/600, timestamps 11px
- [ ] Hover actions: opacity 0→1 on row hover, 4 buttons (copy, thumbs up/down, regenerate)
- [ ] Input area: rounded wrapper, textarea + icon buttons, footer chips with correct colors
- [ ] Scroll: only `.chat-messages` scrolls, thin scrollbar styling applied
- [ ] Works in both conversation and council meeting views

---

## Verification
- [ ] Manual UI review on conversation chat page:
  - Layout structure matches reference exactly
  - Messages display with proper avatar/bubble/time alignment
  - Hover actions appear on desktop hover
  - Input area styling matches reference (colors, borders, radius)
  - Only message area scrolls; header and input stay fixed
- [ ] Test council meeting view applies same patterns
- [ ] Responsive check: mobile layout (padding adjustments, accessible composer)
- [ ] Cross-browser: oklch color support (modern browsers)

## Doc impact
- doc impact: deferred (update `.ai/docs/features/conversations.md` if UX behavior/copy changes)

## Rollback (if applicable)
- Revert view partials, Stimulus tweaks, and CSS adjustments.
