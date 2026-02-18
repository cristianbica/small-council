# UI Framework Research for Small Council (Rails 8 + Importmap)

Date: 2026-02-18

## Goal

Research and recommend a UI framework for Small Council that:
- Works with Rails 8.1.2 and Propshaft
- Uses importmaps (no Node.js build pipeline)
- Provides modern, professional-looking components
- Integrates well with Stimulus and Hotwire/Turbo

## Current Stack

| Component | Version/Tool |
|-----------|--------------|
| Rails | 8.1.2 |
| Asset Pipeline | Propshaft |
| JavaScript | importmap-rails |
| Frontend Framework | Hotwire/Turbo + Stimulus |
| Background Jobs | Solid Queue/Cache/Cable |
| Database | PostgreSQL |

---

## 1. Comparison Matrix

| Framework | Rails 8 Compatible | No Node.js | Component Library | Importmap Works | Hotwire Integration | Setup Complexity |
|-----------|-------------------|------------|-------------------|-----------------|---------------------|------------------|
| **Tailwind CSS** | ✅ Yes | ✅ Yes (standalone binary) | Excellent (DaisyUI, Rails UI, etc.) | ✅ CSS-only | ✅ Excellent | Low |
| **Bootstrap 5** | ✅ Yes | ✅ Yes (gem + CDN) | Good | ✅ With pinning | ⚠️ Manual | Medium |
| **Shoelace** | ✅ Yes | ✅ Yes (CDN) | Built-in (50+ components) | ✅ Yes | ⚠️ Shadow DOM issues | Medium |
| **Bulma** | ✅ Yes | ✅ Yes (CDN) | Limited | ✅ CSS-only | ✅ Good | Very Low |
| **Pico CSS** | ✅ Yes | ✅ Yes (CDN) | None (semantic) | ✅ CSS-only | ✅ Good | Very Low |
| **DaisyUI** | ✅ Yes | ⚠️ Via Tailwind CDN/plugin | Built-in | ✅ Via Tailwind | ✅ Excellent | Low-Medium |

---

## 2. Detailed Analysis

### 2.1 Tailwind CSS (RECOMMENDED)

**Overview:** Utility-first CSS framework with excellent Rails integration via the `tailwindcss-rails` gem.

#### Pros
- **Official Rails support** via `tailwindcss-rails` gem with standalone binary
- **No Node.js required** - uses precompiled Tailwind binary
- **Excellent ecosystem** - DaisyUI, Tailwind UI, Rails UI, Rails Designer
- **Works with importmaps** - CSS-only, no JS bundling needed
- **Active development** - Tailwind v4 released with CSS-first configuration
- **Great Hotwire integration** - many component libraries include Stimulus controllers

#### Cons
- Learning curve for utility classes
- Can lead to verbose HTML without component abstractions
- Requires build step (`bin/rails tailwindcss:build`)

#### Installation
```bash
# Add to Gemfile
gem "tailwindcss-rails"

# Install
bundle install
bin/rails tailwindcss:install
```

#### Configuration (Tailwind v4)
```css
/* app/assets/stylesheets/tailwind/application.css */
@import "tailwindcss";

/* Optional: DaisyUI plugin */
@plugin "./plugins/daisyui.js";
```

#### Procfile.dev
```
web: bin/rails server
css: bin/rails tailwindcss:watch
```

#### Layout
```erb
<%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
```

#### Component Libraries Available
1. **DaisyUI** - Free, 50+ components, pure CSS (no JS)
2. **Rails UI** - Premium gem, Rails-native ERB components, themes
3. **Rails Designer** - Premium, Tailwind components for Rails
4. **Tailwind UI** - Premium, copy-paste HTML components

---

### 2.2 Bootstrap 5

**Overview:** Classic component framework with extensive documentation and community.

#### Pros
- **Familiar** - most developers know Bootstrap
- **Comprehensive components** out of the box
- **Works without Node** via gem + importmap
- **Large ecosystem** of themes and templates

#### Cons
- **No Hotwire integration** - JS conflicts possible
- **Heavier** than utility-first alternatives
- **Dated appearance** without customization
- Requires manual pinning for importmaps

#### Installation
```bash
# Gemfile
gem "bootstrap", "~> 5.3"
gem "sassc-rails"

# Terminal
bundle install
bin/importmap pin bootstrap
```

#### config/importmap.rb
```ruby
pin "popper", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/dist/esm/index.js"
pin "bootstrap", to: "https://ga.jspm.io/npm:bootstrap@5.3.3/dist/js/bootstrap.esm.js"
```

#### app/javascript/application.js
```javascript
import "bootstrap"
```

#### app/assets/stylesheets/application.scss
```scss
@import "bootstrap";
```

---

### 2.3 Shoelace (Web Components)

**Overview:** Modern web component library built with Lit. Framework-agnostic, uses Shadow DOM.

#### Pros
- **Framework agnostic** - works anywhere
- **50+ polished components** - buttons, dialogs, forms, etc.
- **Great theming** - CSS custom properties
- **Accessible** - WCAG compliant
- **CDN-friendly** - can load via importmap

#### Cons
- **Shadow DOM** complicates styling and testing
- **Rails integration** requires manual setup
- **Potential conflicts** with Stimulus/Turbo
- **Less Rails-native** than alternatives

#### Installation (CDN approach)
```erb
<!-- In layout head -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.15.1/cdn/themes/light.css" />
<script type="module" src="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.15.1/cdn/shoelace-autoloader.js"></script>
```

#### Usage
```erb
<sl-button variant="primary">Click me</sl-button>
<sl-dialog label="Dialog">Content here</sl-dialog>
```

---

### 2.4 Bulma

**Overview:** Pure CSS framework with no JavaScript. Clean, modern aesthetic.

#### Pros
- **Zero JavaScript** - no conflicts with Turbo/Stimulus
- **Easy setup** - single CSS file
- **Modern design** - cleaner than Bootstrap
- **Lightweight** - no JS overhead

#### Cons
- **No JS components** - must build your own interactions
- **Less component-rich** than Bootstrap/Shoelace
- **Smaller ecosystem**

#### Installation
```erb
<!-- In layout head -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@1.0.2/css/bulma.min.css">
```

---

### 2.5 Pico CSS

**Overview:** Minimal CSS framework that styles semantic HTML. Almost class-less.

#### Pros
- **Extremely simple** - write semantic HTML, it looks good
- **Tiny** - ~10KB gzipped
- **No classes needed** - semantic HTML approach
- **Great for simple apps**

#### Cons
- **Limited customization** without writing CSS
- **No components** - just styled elements
- **Not ideal for complex UIs**

#### Installation
```erb
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css">
```

---

### 2.6 DaisyUI (Tailwind Plugin)

**Overview:** Component library built on top of Tailwind. Pure CSS, no JS required.

#### Pros
- **Built on Tailwind** - inherits all benefits
- **50+ components** - buttons, cards, modals, etc.
- **No JavaScript** - pure CSS components
- **Multiple themes** included
- **Works with Tailwind v4** via @plugin directive

#### Cons
- **Requires Tailwind setup** first
- **Customization limited** to DaisyUI theming

#### Installation (Tailwind v4 + CDN approach)
```bash
# Download DaisyUI plugin
mkdir -p app/assets/tailwind/plugins
curl -o app/assets/tailwind/plugins/daisyui.js https://cdn.jsdelivr.net/npm/daisyui@5/+esm
```

```css
/* app/assets/stylesheets/tailwind/application.css */
@import "tailwindcss";
@plugin "./plugins/daisyui.js";
```

---

## 3. Recommended Choice

### Primary Recommendation: **Tailwind CSS + DaisyUI**

**Rationale:**
1. **Rails-native** - `tailwindcss-rails` gem provides seamless integration
2. **No Node.js** - standalone binary handles compilation
3. **Component-rich** - DaisyUI provides 50+ ready-to-use components
4. **Importmap-friendly** - CSS-only approach, no JS bundling conflicts
5. **Future-proof** - active development, Tailwind v4 improvements
6. **Flexibility** - can layer on Rails UI or Rails Designer later

### Alternative: **Bulma** (for simplicity)

If Tailwind feels too complex, Bulma offers:
- One-line setup via CDN
- Zero JavaScript conflicts
- Clean, modern design
- Easy to customize with your own CSS

---

## 4. Implementation Notes

### Gemfile Changes

```ruby
# Add Tailwind CSS
gem "tailwindcss-rails"
```

### Configuration Steps

1. **Install Tailwind**
   ```bash
   bundle add tailwindcss-rails
   bin/rails tailwindcss:install
   ```

2. **Add DaisyUI plugin** (optional but recommended)
   ```bash
   mkdir -p app/assets/tailwind/plugins
   curl -o app/assets/tailwind/plugins/daisyui.js https://cdn.jsdelivr.net/npm/daisyui@5/+esm
   ```

3. **Update Tailwind CSS file**
   ```css
   /* app/assets/stylesheets/tailwind/application.css */
   @import "tailwindcss";
   @plugin "./plugins/daisyui.js";
   ```

4. **Update Procfile.dev**
   ```
   web: bin/rails server -p 3000
   css: bin/rails tailwindcss:watch
   ```

5. **Update layout**
   ```erb
   <!-- app/views/layouts/application.html.erb -->
   <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
   ```

6. **Add theme to HTML tag** (for DaisyUI)
   ```erb
   <html data-theme="light">
   ```

### Example Components

```erb
<!-- DaisyUI Button -->
<button class="btn btn-primary">Submit</button>

<!-- DaisyUI Card -->
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Card Title</h2>
    <p>Card content</p>
    <div class="card-actions justify-end">
      <button class="btn btn-primary">Action</button>
    </div>
  </div>
</div>

<!-- DaisyUI Alert -->
<div class="alert alert-success">
  <svg><!-- icon --></svg>
  <span>Success message!</span>
</div>
```

---

## 5. Future Considerations

| Option | When to Consider |
|--------|------------------|
| **Rails UI** | Need complete themes + more Rails-native helpers |
| **Rails Designer** | Want more component variety |
| **Shoelace** | Need framework-agnostic components for future migration |
| **Custom Tailwind** | Outgrowing DaisyUI, need full design control |

---

## Verification

After implementation, verify:
- [ ] `bin/rails tailwindcss:build` runs without errors
- [ ] CSS classes apply correctly in browser
- [ ] No JavaScript console errors
- [ ] Turbo Drive works correctly (navigation without full reload)
- [ ] Stimulus controllers still function

```bash
# Test commands
bin/rails tailwindcss:build
bin/rails server
# Visit http://localhost:3000 and verify styling
```

---

## Doc Impact

- Update: `.ai/docs/features/ui-framework.md` (to be created after implementation)
- Update: `.ai/MEMORY.md` with UI framework choice and commands

---

## Rollback

To remove Tailwind if needed:
```bash
# Remove from Gemfile
# Delete app/assets/stylesheets/tailwind/
# Remove stylesheet_link_tag from layout
# Remove from Procfile.dev
bundle install
```
