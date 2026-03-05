# Councils

Councils are groups of AI advisors that collaborate on conversations.

## Overview

- **Council** = A curated group of AI advisors with a shared purpose
- Councils belong to a space and contain multiple advisors
- Users create councils and configure which advisors participate

## Usage

### Creating a Council
1. Navigate to a space (or use "New Council" from dashboard)
2. Click "New Council"
3. Enter name and description
4. Select advisors to include (optional during creation)
5. Save to create the council

### Managing Advisors
- Add advisors when creating or via council edit page
- Advisors can be reordered (position field)
- Remove advisors from council via council-specific removal action
- Scribe is always assigned to the council and cannot be removed
- Each advisor can have custom prompt overrides per council

### Starting Conversations
- From council page: "New Conversation" button
- Creates conversation with this council's advisors available

## Technical

### Routes
```
/spaces/:space_id/councils     # index, new, create (nested under space)
/councils/:id                  # show, edit, update, destroy, edit_advisors, update_advisors
/councils/:council_id/conversations # index, show, new, create
/councils/generate_description # POST (collection)
/councils/:id/generate_description # POST (member)
```

### Models
- `Council`: name, description, belongs to space and account
- `Council.has_many :council_advisors, dependent: :destroy`
- `Council.has_many :advisors, through: :council_advisors`
- `Council.has_many :conversations, dependent: :destroy`
- `CouncilAdvisor`: join table with `position` and `custom_prompt_override`

### Controllers
- `CouncilsController`: Standard CRUD within space context
- Advisor membership management happens via `edit_advisors` / `update_advisors`
- Creator tracking: `user_id` stored on council for authorization

### Access Control
- All account users can view all councils in their spaces
- Only the creator can edit/update/delete a council
- Only the creator can remove advisors from a council via council page actions

### UI Patterns
- Council cards on space page
- Dedicated council advisor membership editor
- "New Conversation" quick action on council cards
- Reorder advisors via position field

## Council-Advisor Join Model

```ruby
# council_advisors table
council_id              # references council
advisor_id              # references advisor
position                # display/speaking order
custom_prompt_override  # JSONB - per-council prompt adjustments
```

## Relationship to Other Features

| Feature | Relationship |
|---------|--------------|
| Spaces | Councils belong to one space |
| Advisors | Many-to-many via council_advisors |
| Conversations | Belong to a council, inherit advisor set |
| Users | Council has a creator (user_id) |

## Creator Authorization

```ruby
# In CouncilsController
def require_creator
  unless @council.user_id == Current.user.id
    redirect_to @council, alert: "Only the creator can modify this council."
  end
end
```

## Implementation Notes

- Council creation sets `user_id` to `Current.user.id`
- Advisors are assigned/removed through `update_advisors`
- Position field controls display order (lower = first)
- Deleting a council destroys all associated conversations (dependent: :destroy)
- Custom prompt overrides allow per-council advisor customization
