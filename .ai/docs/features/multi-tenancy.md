# Multi-Tenancy

Tenant isolation is enforced with `acts_as_tenant`. Runtime context is carried by `Current.account` and `Current.space`.

## Runtime flow

In `ApplicationController`:

```ruby
def set_current_tenant
  Current.account = Current.user&.account
  ActsAsTenant.current_tenant = Current.account
end

def set_current_space
  Current.space = Current.account.spaces.find_by(id: session[:space_id]) if session[:space_id]
  Current.space ||= Current.account.spaces.first
  Current.space ||= Current.account.spaces.create!(name: "General", description: "Default space for your councils")
end
```

## Scope model

- `account_id` is present on tenant data tables and enforced by model-level `acts_as_tenant :account`
- Controllers use `Current.account` and `Current.space` to bound lookups (for example `Current.space.conversations.find(params[:id])`)
- Cross-space access in controllers returns `404` for missing scoped records

## Authentication tie-in

- Sessions resolve `Current.session`
- `Current.user` is delegated from session
- Tenant is derived from `Current.user.account`

## Note on user email uniqueness

`User` currently validates globally unique email (`validates :email, uniqueness: true`) with a unique DB index on `users.email`.
