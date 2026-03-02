# UI Components

Reusable UI patterns and components for Small Council.

## DaisyUI Usage (Tailwind v4 + DaisyUI v5)

This repo uses DaisyUI as a Tailwind plugin in `app/assets/tailwind/application.css`:

- `@import "tailwindcss";`
- `@plugin "./daisyui.mjs" { themes: all; }`

Use DaisyUI + Tailwind utilities first; avoid custom CSS unless a component cannot be expressed with existing classes.

### Class Composition Rule

Compose classes in this order:

1. Component class (`btn`, `card`, `input`, `alert`)
2. DaisyUI modifiers (style/color/size/behavior, e.g. `btn-primary btn-sm`)
3. Tailwind utilities for spacing/layout/responsiveness (e.g. `w-full md:w-auto`)

Example:

```erb
<%= form.submit "Save",
    class: "btn btn-primary btn-sm w-full md:w-auto" %>
```

### Theme + Color Rule

- Prefer semantic DaisyUI color tokens (`primary`, `secondary`, `accent`, `base-*`, `*-content`) over raw palette values.
- Prefer component color classes (`btn-primary`, `alert-error`, `badge-success`) over `text-gray-*`/`bg-gray-*` so themes stay readable.
- Avoid `dark:` variants for DaisyUI semantic colors; theme tokens already adapt.
- Keep global theme on the layout root (`data-theme`) and avoid per-component hard-coded color overrides.

### Layout + Responsiveness Rule

- Use Tailwind responsive utilities for layout (`sm:`, `md:`, `lg:`) with DaisyUI components.
- For grouped controls, prefer DaisyUI structure classes (`join`, `menu`, `tabs`) plus responsive direction utilities.
- Keep page rhythm with existing spacing standards in this file (`space-y-6`, `gap-4`, etc.).

### Customization Rule

- First choice: DaisyUI component + modifier classes.
- Second choice: Tailwind utility classes.
- Last resort: utility `!` override (for specificity conflicts only; use sparingly).

Example last resort:

```erb
<button class="btn btn-primary bg-red-500!">Danger</button>
```

### Anti-patterns

- Do not introduce new one-off CSS classes for common controls already covered by DaisyUI.
- Do not mix conflicting component families on the same element (example: `btn` + `input`).
- Do not rely on fixed Tailwind gray text colors for core surfaces; use `*-content` semantics.
- Do not apply `bg-base-100 text-base-content` on `body` unless needed for a specific reason.

## Form Field Pattern

Standard form field with validation support:

```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">
      Field Label
      <span class="text-error" aria-label="required">*</span>
    </span>
    <span class="label-text-alt text-base-content/60">Optional hint</span>
  </label>
  <%= form.text_field :field_name,
      class: "input input-bordered #{'input-error' if form.object.errors[:field_name].any?}",
      required: true %>
  <% if form.object.errors[:field_name].any? %>
    <label class="label">
      <span class="label-text-alt text-error flex items-center gap-1">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <%= form.object.errors[:field_name].first %>
      </span>
    </label>
  <% end %>
</div>
```

### Form Error Alert

Top-of-form error summary:

```erb
<% if form.object.errors.any? %>
  <div class="alert alert-error">
    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 shrink-0 stroke-current" fill="none" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    <div>
      <h3 class="font-bold"><%= pluralize(form.object.errors.count, "error") %> prohibited this from being saved:</h3>
      <ul class="mt-1 list-disc list-inside text-sm">
        <% form.object.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  </div>
<% end %>
```

### Checkbox Pattern

```erb
<div class="form-control">
  <label class="label cursor-pointer justify-start gap-3">
    <%= form.check_box :enabled, class: "checkbox checkbox-primary" %>
    <span class="label-text">Enabled</span>
  </label>
</div>
```

## Empty State Pattern

Use the shared partial for consistent empty states:

```erb
<%= render "shared/empty_state",
    title: "No items yet",
    description: "Description of what to do next.",
    action_path: new_item_path,
    action_text: "Create Item" %>
```

Optional: Include an icon:

```erb
<%= render "shared/empty_state",
    icon: content_tag(:svg, "...", class: "w-16 h-16 text-base-content/30"),
    title: "No items yet",
    description: "Description..." %>
```

## Card with Header Pattern

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

## Status Badge Pattern

Use helper methods for consistent status badges:

```erb
<span class="badge <%= status_badge_class(object) %> badge-sm">
  <%= object.status %>
</span>
```

Helper method example:

```ruby
def status_badge_class(conversation)
  case conversation.status
  when "active" then "badge-success"
  when "resolved" then "badge-primary"
  when "archived" then "badge-ghost"
  else "badge-ghost"
  end
end
```

## Navigation Active State

```erb
<%= link_to dashboard_path,
    class: "#{'active' if current_page?(dashboard_path)}" do %>
  Dashboard
<% end %>
```

Or for controller-based matching:

```erb
<%= link_to councils_path,
    class: "#{'active' if controller_name == 'councils'}" do %>
  Councils
<% end %>
```

## Form Actions Pattern

```erb
<div class="card-actions justify-end">
  <%= link_to "Cancel", back_path, class: "btn btn-ghost" %>
  <%= form.submit "Save", class: "btn btn-primary" %>
</div>
```

## Stats Card Pattern

```erb
<div class="stat bg-base-100 shadow rounded-lg">
  <div class="stat-title">Label</div>
  <div class="stat-value"><%= value %></div>
  <div class="stat-desc">Description</div>
</div>
```

## Search Input Pattern

```erb
<div class="form-control flex-1">
  <div class="relative">
    <span class="absolute inset-y-0 left-0 flex items-center pl-3 text-base-content/50">
      <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
    </span>
    <%= f.text_field :q,
        placeholder: "Search...",
        class: "input input-bordered w-full pl-10" %>
  </div>
</div>
```

## Shared Partials

### Form Field Partial

`app/views/shared/_form_field.html.erb` - Reusable form field with validation:

```erb
<%= render layout: "shared/form_field",
    locals: { label: "Name", required: true, hint: "Helper text", errors: form.object.errors[:name] } do %>
  <%= form.text_field :name, class: "input input-bordered" %>
<% end %>
```

Parameters:
- `label` (required): Field label text
- `required` (optional): Show required asterisk if true
- `hint` (optional): Helper text shown in label-alt
- `errors` (optional): Array of error messages

## Spacing Standards

- Page container: `space-y-6`
- Form sections: `space-y-4`
- Card body padding: default `card-body`
- Between cards in grid: `gap-4`
- List items: `space-y-3`

## Typography Standards

- Page titles: `text-3xl font-bold`
- Section titles: `text-xl font-bold` or `card-title`
- Body text: default
- Helper text: `text-sm text-base-content/60`
- Meta text: `text-xs text-base-content/50`
