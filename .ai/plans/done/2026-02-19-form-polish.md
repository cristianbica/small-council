# Form Polish Plan - Fix Alignment & Styling Issues

Date: 2026-02-19

## Issues to Fix

### 1. Input Alignment
**Problem**: Inputs have inconsistent widths - some use `w-full`, others don't. Labels and inputs don't align properly.

**Solution**: 
- All inputs must use `w-full` to fill their container
- Form controls should have consistent structure

### 2. Optional Field Styling
**Problem**: Currently showing "Optional" text explicitly in label-text-alt which looks cluttered and unprofessional.

**Solution**:
- Remove explicit "Optional" text
- Only show required marker (*) on required fields
- Optional fields have no marker (cleaner look)

### 3. Empty State Centering
**Problem**: Empty state content may not be properly centered.

**Solution**:
- Ensure hero-content uses proper centering classes
- Icon should be centered
- Text should be centered

### 4. Form Layout Inconsistency
**Problem**: Some forms wrap the card inside the form, others wrap the form inside the card.

**Solution**:
- Standardize on: Card > Card-body > Form structure
- Form should fill the card body

## Files to Update

### High Priority (Fix alignment & optional styling)
1. `app/views/providers/new.html.erb`
2. `app/views/providers/edit.html.erb`
3. `app/views/councils/_form.html.erb`
4. `app/views/advisors/_form.html.erb`
5. `app/views/spaces/_form.html.erb`
6. `app/views/conversations/new.html.erb`

### Medium Priority (Consistency)
7. `app/views/shared/_empty_state.html.erb` - Verify centering
8. `app/views/sessions/new.html.erb` - Already good, verify consistency
9. `app/views/registrations/new.html.erb` - Verify consistency

## Implementation Details

### Standard Form Field Pattern

```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">
      Field Name
      <span class="text-error">*</span>
    </span>
  </label>
  <%= form.text_field :field,
      class: "input input-bordered w-full #{'input-error' if form.object.errors[:field].any?}",
      placeholder: "Placeholder text",
      required: true %>
  <% if form.object.errors[:field].any? %>
    <label class="label">
      <span class="label-text-alt text-error"><%= form.object.errors[:field].first %></span>
    </label>
  <% end %>
</div>
```

### Optional Field Pattern (No Marker)

```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">Description</span>
  </label>
  <%= form.text_area :description,
      class: "textarea textarea-bordered w-full #{'textarea-error' if form.object.errors[:description].any?}",
      rows: 3,
      placeholder: "What is this for?" %>
  <% if form.object.errors[:description].any? %>
    <label class="label">
      <span class="label-text-alt text-error"><%= form.object.errors[:description].first %></span>
    </label>
  <% end %>
</div>
```

### Form with Helper Text Pattern

```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">
      API Key
      <span class="text-error">*</span>
    </span>
  </label>
  <%= form.password_field :api_key,
      class: "input input-bordered w-full #{'input-error' if form.object.errors[:api_key].any?}",
      placeholder: "sk-...",
      required: true %>
  <label class="label">
    <span class="label-text-alt text-base-content/60">Your API key is encrypted at rest</span>
  </label>
  <% if form.object.errors[:api_key].any? %>
    <label class="label">
      <span class="label-text-alt text-error"><%= form.object.errors[:api_key].first %></span>
    </label>
  <% end %>
</div>
```

## Acceptance Criteria

- [ ] All inputs use `w-full` class consistently
- [ ] Required fields show red asterisk (*)
- [ ] Optional fields have NO marker (not "Optional" text)
- [ ] All form controls align properly within their containers
- [ ] Empty states are properly centered
- [ ] Form structure is consistent: Card > Card-body > Form
- [ ] Helper text (when present) uses `label-text-alt` below the input
- [ ] Error messages appear below inputs with `label-text-alt text-error`

## Timeline

- 6 form files: 1.5 hours
- Testing & verification: 0.5 hours
- **Total: ~2 hours**
