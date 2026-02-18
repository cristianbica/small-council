# Multi-Tenancy

Multi-tenancy architecture with account scoping.

## Architecture

**Account** is the root tenant entity:
- All data belongs to an account
- Users are scoped to accounts (email uniqueness per account)
- Future: `acts_as_tenant` gem will enforce scoping

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

## Future: acts_as_tenant

Models have comments ready for activation:
```ruby
# acts_as_tenant :account will be enabled when gem is installed
```

When enabled:
- Automatic scoping on all queries
- Account ID required for all records
- Set tenant via subdomain or session

## Data Model

```
Account
├── Users
├── Advisors
├── Councils
├── Conversations
├── Messages
└── UsageRecords
```

All tables except `accounts` have `account_id` column for scoping.
