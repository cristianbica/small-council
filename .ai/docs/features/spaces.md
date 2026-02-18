# Spaces

Spaces are contextual workspaces that organize councils. Each account can have multiple spaces, and users switch between spaces via session-based context.

## Overview

- **Space** = A container for related councils (e.g., "Product Team", "Q1 Planning")
- Spaces provide organization and separation of concerns within an account
- Switching spaces changes the context for all council-related operations

## Usage

### Creating a Space
1. Navigate to "Spaces" in the navigation
2. Click "New Space"
3. Enter name and optional description
4. Save to create and automatically switch to the new space

### Switching Spaces
1. Click a space name in the spaces list
2. The space context is stored in session (`session[:space_id]`)
3. All subsequent council operations happen within that space

### Viewing Space Councils
- When you enter a space, you see only councils belonging to that space
- The space context persists across requests via `Current.space`

## Technical

### Routes
```
/spaces                  # index, new, create
/spaces/:id             # show (switches context, redirects to councils)
/spaces/:id/edit        # edit, update
```

### Models
- `Space`: name, description, belongs to account
- `Space.has_many :councils, dependent: :destroy`
- `Current.space` - active space context (via CurrentAttributes)

### Controllers
- `SpacesController`: CRUD operations + context switching
- Context switch: `session[:space_id] = @space.id; Current.space = @space`

### Access Control
- All account users can view all spaces in their account
- All account users can create spaces
- No role-based restrictions in Phase 1

### UI Patterns
- Space cards with council count badges
- "Current space" indicator in navigation
- Quick switch dropdown in navbar

## Data Flow

```
User clicks space
    ↓
SpacesController#show sets session[:space_id]
    ↓
ApplicationController sets Current.space from session
    ↓
All council queries scoped to Current.space
```

## Relationship to Other Features

| Feature | Relationship |
|---------|--------------|
| Councils | Belong to exactly one space |
| Conversations | Inherited through council → space |
| Current | `Current.space` provides active context |

## Implementation Notes

- Space switching is session-based (not URL-based) for cleaner URLs
- `Current.space` is set in ApplicationController for all requests
- If no space is selected, user is prompted to create or select one
- Space-scoped queries: `Current.space.councils`, `Current.account.spaces`
