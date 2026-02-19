---
name: frontend-development
description: Build polished Rails frontend experiences with Tailwind and DaisyUI, emphasizing clarity, accessibility, and practical UX.
compatibility: opencode
metadata:
  stack: ruby-on-rails-tailwind-daisyui
  focus: frontend-ux
  audience: product-engineering
---

## What I do
- Build and refactor Rails views (ERB), partials, and view components with clean structure and reusable patterns.
- Implement UI using Tailwind utility classes and DaisyUI components without introducing custom design systems unless requested.
- Improve UX for forms, states, and navigation: loading, empty, success, error, and validation flows.
- Keep interfaces accessible (semantic HTML, labels, keyboard focus, ARIA only when needed, contrast-safe choices).
- Preserve responsiveness across mobile, tablet, and desktop while keeping layouts simple and scannable.

## Technical standards
- Prefer server-rendered Rails patterns first; only add JavaScript/Stimulus when interaction truly needs it.
- Keep Tailwind class usage intentional and consistent with existing project conventions.
- Use DaisyUI primitives (`btn`, `card`, `alert`, `badge`, `input`, `select`, `textarea`, `modal`, `tabs`, etc.) to maintain a coherent UI language.
- Avoid hardcoded colors or ad hoc CSS when DaisyUI/Tailwind tokens already solve the need.
- Minimize DOM complexity and avoid fragile nested wrappers.

## UX standards
- Prioritize legibility and hierarchy: clear headings, concise labels, meaningful spacing, and obvious primary actions.
- Ensure predictable behavior: destructive actions are explicit, confirmations are clear, and outcomes are visible.
- Reduce user effort: sensible defaults, short forms, grouped inputs, and inline guidance where needed.
- Design for state completeness: each screen should gracefully handle empty, loading, success, and failure states.
- Prefer progressive enhancement over JS-heavy interactions.

## Rails + frontend workflow
1. Understand the user flow and identify the target Rails views/partials.
2. Sketch the smallest viable UI structure using semantic HTML.
3. Apply Tailwind layout/spacing utilities, then DaisyUI component classes.
4. Add interaction polish (focus, hover, disabled, validation and flash messaging states).
5. Verify responsive behavior and accessibility basics.
6. Keep changes localized and consistent with existing conventions.

## When to use me
Use this skill when you need UI work in a Rails app that should feel modern, clean, and production-ready with Tailwind + DaisyUI.

Typical requests:
- “Build a new settings screen in Rails using DaisyUI cards and forms.”
- “Refactor this ERB page to improve visual hierarchy and mobile layout.”
- “Improve form UX and validation feedback without overcomplicating the frontend.”

## Guardrails
- Do not invent new pages, themes, or complex interactions unless requested.
- Do not introduce additional frontend frameworks when Rails + Tailwind + DaisyUI are sufficient.
- Keep scope tight, reusable, and easy for a Rails team to maintain.
