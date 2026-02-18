# Security Testing Patterns

Security tests verify the application properly enforces authorization boundaries and prevents unauthorized access to data and functionality.

## Core Security Test Categories

### 1. Tenant Isolation Tests

Verify users cannot access resources from other accounts.

```ruby
# Pattern: Test accessing resource from different account
test "cannot access [resource] from different account" do
  sign_in_as(users(:one))
  set_tenant(accounts(:one))
  
  # Create resource in other account without tenant scoping
  other_account = ActsAsTenant.without_tenant do
    Account.create!(name: "Other", slug: "other-#{Time.now.to_i}")
  end
  other_resource = ActsAsTenant.without_tenant do
    other_account.[resources].create!(...)
  end
  
  get [resource]_url(other_resource)
  assert_response :not_found # or :forbidden
end
```

### 2. Resource Ownership Tests

Verify only creators can modify/delete their resources.

```ruby
# Pattern: Test non-creator cannot modify resource
test "non-creator cannot [action] [resource]" do
  sign_in_as(users(:regular)) # Not the creator
  set_tenant(accounts(:one))
  
  # Resource created by admin
  resource = [resources](:one) # created by admin in fixtures
  
  assert_no_difference "[Resource].count" do
    [action] [resource]_url(resource)
  end
  assert_redirected_to [appropriate_path]
  assert_equal "[Error message]", flash[:alert]
end
```

### 3. ID Manipulation Tests

Verify changing IDs in URLs doesn't grant unauthorized access.

```ruby
# Pattern: Test ID manipulation in URLs
test "cannot access [resource] from different [parent] via ID manipulation" do
  sign_in_as(users(:one))
  set_tenant(accounts(:one))
  
  other_parent = create_other_parent
  other_resource = create_resource_in(other_parent)
  
  # Try to access via direct URL
  get [resource]_url(other_resource)
  assert_response :not_found
end
```

### 4. Parameter Tampering Tests

Verify users cannot manipulate form parameters to bypass security.

```ruby
# Pattern: Test form parameter manipulation
test "cannot manipulate [param] via [resource] form" do
  sign_in_as(users(:one))
  set_tenant(accounts(:one))
  
  other_account = accounts(:two)
  
  post [resources]_url, params: { 
    [resource]: { 
      name: "Test",
      [param]: other_account.id # Attempt to set unauthorized value
    } 
  }
  
  created = [Resource].last
  assert_equal users(:one).account_id, created.account_id
  refute_equal other_account.id, created.account_id
end
```

## Security Test Checklist

For each controller/resource:

- [ ] Unauthenticated users redirected to sign in
- [ ] Authenticated users see only their account's data
- [ ] Users cannot access other accounts' resources
- [ ] Users cannot modify resources they don't own
- [ ] Users cannot delete resources they don't own
- [ ] ID manipulation in URLs returns 404/not_found
- [ ] Form parameters cannot override ownership/account
- [ ] Nested resources verify parent ownership

## Common Security Assertions

```ruby
# Access denied assertions
assert_response :not_found
assert_response :forbidden
assert_redirected_to sign_in_url
assert_redirected_to appropriate_fallback_path

# Data integrity assertions
assert_equal expected_account_id, resource.account_id
refute_equal other_account_id, resource.account_id
assert_no_difference "Resource.count" do
  # action that should fail
end

# Flash message assertions
assert_equal "Only the creator can modify this council.", flash[:alert]
assert_equal "Council not found.", flash[:alert]
```

## Test Helper Patterns

```ruby
# Create resources in other accounts without scoping
def create_in_other_account
  ActsAsTenant.without_tenant do
    account = Account.create!(...)
    yield account
  end
end

# Verify tenant scoping works
def assert_tenant_scoped(model_class)
  set_tenant(accounts(:one))
  assert model_class.where(account: accounts(:one)).exists?
  assert_not model_class.where(account: accounts(:two)).exists?
end
```

## Testing Different User Roles

```ruby
# Regular member tests
test "member can [action]" do
  sign_in_as(users(:member))
  # test member permissions
end

# Admin tests
test "admin can [action]" do
  sign_in_as(users(:admin))
  # test admin permissions
end

# Cross-role boundary tests
test "member cannot [privileged action]" do
  sign_in_as(users(:member))
  # test member is blocked from admin action
end
```
