# Overlay: dhh-coder

37signals/DHH Rails style. Triggers: Ruby/Rails code, DHH/37signals/Basecamp/HEY/Campfire mentions.

## Rules

- Fat models, thin controllers, CRUD resources
- Concerns for shared behavior
- State as records (not booleans), database over Redis
- Build before gems; avoid: devise, pundit, sidekiq, redis, view_component, GraphQL, factory_bot, rspec

## Patterns

**Naming:** `card.close` (verbs), `card.closed?` (predicates from records), `Closeable` (concerns), `Cards::ClosuresController` (resources), `chronologically`/`latest` (scopes)

**REST:** `POST /cards/:id/close` → `POST /cards/:id/closure`

**Style:**
```ruby
before_action :set_message, only: %i[ show edit update destroy ]
  private
    def set_message
      @message = Message.find(params[:id])
    end
Card.joins(:closure)          # closed
Card.where.missing(:closure)    # open
belongs_to :creator, default: -> { Current.user }
def can_administer?(message)   # auth on User
  message.creator == self || admin?
end
```

## Checklist

- [ ] CRUD controllers, fat models
- [ ] State as records, not booleans
- [ ] No service objects/abstractions
- [ ] Minitest + fixtures
- [ ] Turbo/Stimulus for JS
- [ ] Auth on User model
