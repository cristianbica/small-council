# UI Framework

Tailwind CSS v4 + DaisyUI v5 for a Rails-native, Node-free styling solution.

## Why This Choice

- **No Node.js required** - `tailwindcss-rails` gem bundles Tailwind as a standalone executable
- **Rails-native** - integrates with asset pipeline, hot reloading via `bin/dev`
- **Component-rich** - DaisyUI provides 50+ pre-built components (buttons, cards, forms, etc.)
- **Semantic classes** - `btn btn-primary` instead of long utility chains

## Key Commands

| Command | Purpose |
|---------|---------|
| `bin/rails tailwindcss:build` | One-time CSS build |
| `bin/rails tailwindcss:watch` | Watch for changes (auto-rebuild) |
| `bin/dev` | Full dev server (web + CSS watch) |

## Configuration

- **Config**: `app/assets/tailwind/application.css`
- **Output**: `app/assets/builds/tailwind.css`
- **Plugin**: `app/assets/tailwind/daisyui.mjs` (downloaded standalone)

```css
/* application.css */
@import "tailwindcss";
@source not "./daisyui{,*}.mjs";  /* Exclude DaisyUI from scanning */
@plugin "./daisyui.mjs";          /* Load DaisyUI plugin */
```

## Theme

Set via `data-theme` attribute on `<html>`:

```erb
<html data-theme="light">
```

Available DaisyUI themes: `light`, `dark`, `cupcake`, `bumblebee`, `emerald`, `corporate`, `synthwave`, `retro`, `cyberpunk`, `valentine`, `halloween`, `garden`, `forest`, `aqua`, `lofi`, `pastel`, `fantasy`, `wireframe`, `cmyk`, `autumn`, `business`, `acid`, `lemonade`, `night`, `coffee`, `winter`

To switch themes, change `data-theme` in `app/views/layouts/application.html.erb`.

## DaisyUI Components Used

| Component | Classes | Example Location |
|-----------|---------|------------------|
| Button | `btn`, `btn-primary`, `btn-ghost`, `btn-sm` | Navigation, forms |
| Card | `card`, `card-body`, `card-title` | Auth forms |
| Navbar | `navbar`, `navbar-start`, `navbar-center`, `navbar-end` | `_navigation.html.erb` |
| Menu | `menu`, `menu-horizontal`, `menu-sm` | Navigation |
| Alert | `alert`, `alert-success`, `alert-error`, `alert-warning`, `alert-info` | Flash messages |
| Form Control | `form-control`, `label`, `label-text`, `input`, `input-bordered` | Auth forms |
| Dropdown | `dropdown`, `dropdown-end`, `dropdown-content` | User menu |
| Link | `link`, `link-primary`, `link-hover` | Various |
| Divider | `divider` | Auth forms |

## Common Patterns

### Button

```erb
<%= button_to "Save", path, class: "btn btn-primary" %>
<%= link_to "Cancel", path, class: "btn btn-ghost" %>
```

Variants: `btn-primary`, `btn-secondary`, `btn-accent`, `btn-ghost`, `btn-outline`, `btn-link`

Sizes: `btn-lg`, `btn-md`, `btn-sm`, `btn-xs`

### Form Field

```erb
<div class="form-control">
  <label class="label">
    <span class="label-text">Email</span>
  </label>
  <%= form.email_field :email, class: "input input-bordered w-full" %>
  <label class="label">
    <span class="label-text-alt">Helper text</span>
  </label>
</div>
```

### Card

```erb
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Title</h2>
    <p>Content here</p>
    <div class="card-actions justify-end">
      <button class="btn btn-primary">Action</button>
    </div>
  </div>
</div>
```

### Alert (Flash Messages)

```erb
<div class="alert alert-success">
  <svg><!-- icon --></svg>
  <span>Success message</span>
</div>
```

## Adding New Components

1. Browse [DaisyUI Components](https://daisyui.com/components/)
2. Copy the HTML classes into your ERB template
3. Tailwind will auto-detect classes during watch/build

No additional configuration needed - DaisyUI classes are ready to use.

## Customization

For custom styles beyond DaisyUI:

1. Add CSS to `app/assets/stylesheets/application.css`
2. Or extend Tailwind in `app/assets/tailwind/application.css`:

```css
@theme {
  --color-brand: oklch(0.7 0.2 150);
}
```

See [Tailwind CSS v4 docs](https://tailwindcss.com/docs/v4-beta) for the new `@theme` syntax.
