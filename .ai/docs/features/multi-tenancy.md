# Multi-Tenancy

Multi-tenancy with automatic query scoping via `acts_as_tenant` gem.

## Architecture

**Account** is the root tenant entity:
- All data belongs to an account
- Users are scoped to accounts (email uniqueness per account)
- `acts_as_tenant` gem enforces automatic query scoping

## Integration with Authentication

### Account Creation During Signup
When a user signs up:
1. Account is created (name + slug)
2. First user is created as admin
3. User automatically belongs to that account
4. Session created, user logged in

### User Scoping
```ruby
class User < ApplicationRecord
  belongs_to :account
  validates :email, uniqueness: { scope: :account_id }
end
```

Same email can exist across different accounts.

### Session Scoping
Sessions belong to users, so access to account data is through:
```
Current.user.account
```

## acts_as_tenant Configuration

### Automatic Tenant Setting
Tenant is set in `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_current_tenant

  private

  def set_current_tenant
    if Current.user
      Current.account = Current.user.account
      set_current_tenant(Current.account)
    end
  end
end
```

### Current.account Attribute
After sign-in, `Current.account` is available:

```ruby
# In controllers/views
Current.account  # => Account record for the signed-in user
```

### Automatic Query Scoping
All queries are automatically scoped to the current account:

```sql
-- Queries include automatic WHERE clause
SELECT * FROM users WHERE account_id = X
SELECT * FROM conversations WHERE account_id = X
```

- Account ID required for all records (enforced by gem)
- No manual scoping needed in application code

## Data Model

```
Account
├── Users
├── Spaces
├── Advisors
├── Councils
├── Conversations
├── Messages
├── UsageRecords
├── Providers
└── LlmModels
```

All tables except `accounts` have `account_id` column for scoping.

## Query Scoping

All queries automatically include `WHERE account_id = X`:

```ruby
# Controller (implicit scoping)
@spaces = Current.account.spaces

# Model level (automatic)
Space.all  # => SELECT * FROM spaces WHERE account_id = 1

# Bypass for admin/migration tasks
ActsAsTenant.without_tenant { Space.count }
```
