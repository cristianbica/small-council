# Plan: Enable acts_as_tenant for Multi-Tenancy

Date: 2026-02-18

## Goal

Enable the `acts_as_tenant` gem to provide automatic query scoping by account_id across all models (except Account). This ensures users only see data from their own account, with tenant identification via session (not subdomains).

## Non-goals

- Subdomain-based tenant identification
- Cross-tenant data sharing (beyond existing global advisors pattern)
- Public/anonymous access to tenant data
- API token-based tenant resolution (session-only for now)

## Scope + assumptions

- `acts_as_tenant` gem needs to be added to Gemfile
- All tables except `accounts` have `account_id` column (verified in schema.rb)
- Tenant is set via session (already using authentication-zero pattern)
- Current.user.account provides the tenant context
- Tests use fixtures; need to ensure tenant is set properly in test context
- No need to scope the join table `CouncilAdvisor` directly (scoped through its associations)

## Evidence from codebase inspection

- **Gemfile**: `acts_as_tenant` is NOT present - must add it
- **Schema.rb**: All tables except `accounts` have `account_id` (lines 29, 45, 62, 74, 89, 117, 133)
- **Models with account_id**: User, Advisor, Council, Conversation, Message, UsageRecord, CouncilAdvisor
- **Current model**: Has `session`, `user_agent`, `ip_address` - needs `account` attribute
- **ApplicationController**: Authenticates via `Session.find_by_id(cookies.signed[:session_token])` and sets `Current.session`
- **Models already have**: `# acts_as_tenant :account will be enabled when gem is installed` comments
- **Session-based auth**: Already implemented via authentication-zero pattern

## Steps

### Phase 1: Add acts_as_tenant Gem

1. **Add gem to Gemfile**
   
   File: `Gemfile`
   
   ```ruby
   # Multi-tenancy support
   gem "acts_as_tenant", "~> 1.0"
   ```

2. **Bundle install**
   ```bash
   bundle install
   ```

### Phase 2: Update Current Attributes for Tenant

3. **Add account to Current attributes**
   
   File: `app/models/current.rb`
   
   ```ruby
   class Current < ActiveSupport::CurrentAttributes
     attribute :session
     attribute :user_agent, :ip_address
     attribute :account  # Add this line
   
     delegate :user, to: :session, allow_nil: true
   end
   ```

### Phase 3: Set Tenant in ApplicationController

4. **Add tenant setting to authentication flow**
   
   File: `app/controllers/application_controller.rb`
   
   ```ruby
   class ApplicationController < ActionController::Base
     # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
     allow_browser versions: :modern
   
     before_action :set_current_request_details
     before_action :authenticate
     before_action :set_current_tenant  # Add this line
   
     helper_method :authenticated?
   
     private
   
     def authenticate
       if session_record = Session.find_by_id(cookies.signed[:session_token])
         Current.session = session_record
       else
         redirect_to sign_in_path
       end
     end
   
     def authenticated?
       Current.session.present?
     end
   
     def set_current_request_details
       Current.user_agent = request.user_agent
       Current.ip_address = request.ip
     end
   
     # Add this method
     def set_current_tenant
       Current.account = Current.user&.account
       ActsAsTenant.current_tenant = Current.account
     end
   end
   ```

### Phase 4: Enable acts_as_tenant in Models

5. **Update User model**
   
   File: `app/models/user.rb`
   
   ```ruby
   class User < ApplicationRecord
     acts_as_tenant :account  # Replace comment with this
     belongs_to :account
   
     has_many :councils, dependent: :destroy
     has_many :conversations, dependent: :destroy
     has_many :messages, as: :sender, dependent: :destroy
     has_many :sessions, dependent: :destroy
   
     has_secure_password
   
     # Token support for password reset and email verification
     generates_token_for :password_reset, expires_in: 20.minutes do
       password_salt&.last(10)
     end
   
     generates_token_for :email_verification, expires_in: 24.hours do
       email
     end
   
     enum :role, {
       member: "member",
       admin: "admin"
     }, default: "member"
   
     validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
     validates :email, uniqueness: { scope: :account_id }
     validates :account, presence: true
   end
   ```

6. **Update Advisor model**
   
   File: `app/models/advisor.rb`
   
   ```ruby
   class Advisor < ApplicationRecord
     acts_as_tenant :account  # Replace comment with this
     belongs_to :account
   
     has_many :council_advisors, dependent: :destroy
     has_many :councils, through: :council_advisors
     has_many :messages, as: :sender, dependent: :destroy
   
     enum :model_provider, {
       openai: "openai",
       anthropic: "anthropic",
       gemini: "gemini"
     }
   
     validates :name, presence: true
     validates :system_prompt, presence: true
     validates :model_provider, presence: true
     validates :model_id, presence: true
     validates :account, presence: true
   
     scope :global, -> { where(global: true) }
     scope :custom, -> { where(global: false) }
   end
   ```

7. **Update Council model**
   
   File: `app/models/council.rb`
   
   ```ruby
   class Council < ApplicationRecord
     acts_as_tenant :account  # Replace comment with this
     belongs_to :account
     belongs_to :user
   
     has_many :council_advisors, dependent: :destroy
     has_many :advisors, through: :council_advisors
     has_many :conversations, dependent: :destroy
   
     enum :visibility, {
       private_visibility: "private",
       shared: "shared"
     }, default: "private", prefix: true
   
     validates :name, presence: true
     validates :account, presence: true
     validates :user, presence: true
   end
   ```

8. **Update Conversation model**
   
   File: `app/models/conversation.rb`
   
   ```ruby
   class Conversation < ApplicationRecord
     acts_as_tenant :account  # Replace comment with this
     belongs_to :account
     belongs_to :council
     belongs_to :user
   
     has_many :messages, dependent: :destroy
   
     enum :status, {
       active: "active",
       archived: "archived"
     }, default: "active"
   
     validates :account, presence: true
     validates :council, presence: true
     validates :user, presence: true
   
     scope :recent, -> { order(last_message_at: :desc) }
     scope :active, -> { where(status: "active") }
   end
   ```

9. **Update Message model**
   
   File: `app/models/message.rb`
   
   ```ruby
   class Message < ApplicationRecord
     acts_as_tenant :account  # Replace comment with this
     belongs_to :account
     belongs_to :conversation
     belongs_to :sender, polymorphic: true
   
     has_one :usage_record, dependent: :destroy
   
     enum :role, {
       user: "user",
       advisor: "advisor",
       system: "system"
     }
   
     enum :status, {
       pending: "pending",
       complete: "complete",
       error: "error"
     }, default: "complete"
   
     validates :account, presence: true
     validates :conversation, presence: true
     validates :sender, presence: true
     validates :role, presence: true
   
     scope :by_role, ->(role) { where(role: role) }
     scope :chronological, -> { order(created_at: :asc) }
   end
   ```

10. **Update UsageRecord model**
    
    File: `app/models/usage_record.rb`
    
    ```ruby
    class UsageRecord < ApplicationRecord
      acts_as_tenant :account  # Replace comment with this
      belongs_to :account
      belongs_to :message, optional: true
    
      validates :account, presence: true
      validates :provider, presence: true
      validates :model, presence: true
      validates :input_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validates :output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validates :cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    
      scope :by_provider, ->(provider) { where(provider: provider) }
      scope :by_model, ->(model) { where(model: model) }
      scope :recorded_since, ->(time) { where("recorded_at >= ?", time) }
      scope :recorded_before, ->(time) { where("recorded_at < ?", time) }
    
      # Helper to calculate total tokens
      def total_tokens
        input_tokens + output_tokens
      end
    
      # Helper to format cost as dollars
      def cost_dollars
        cost_cents / 100.0
      end
    end
    ```

11. **Update CouncilAdvisor model (join table - scoped through associations)**
    
    File: `app/models/council_advisor.rb`
    
    ```ruby
    class CouncilAdvisor < ApplicationRecord
      # No acts_as_tenant needed - join table, scoped through council/advisor
      belongs_to :council
      belongs_to :advisor
    
      validates :council, presence: true
      validates :advisor, presence: true
      validates :advisor_id, uniqueness: { scope: :council_id }
      validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    end
    ```

### Phase 5: Update Test Helper for Tenant Context

12. **Add tenant reset and test helpers**
    
    File: `test/test_helper.rb`
    
    ```ruby
    ENV["RAILS_ENV"] ||= "test"
    require_relative "../config/environment"
    require "rails/test_help"
    
    class ActiveSupport::TestCase
      # Run tests in parallel with specified workers
      parallelize(workers: :number_of_processors)
    
      # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
      fixtures :all
    
      # Add more helper methods to be used all tests here...
      
      # Helper to set tenant in model tests
      def set_tenant(account)
        ActsAsTenant.current_tenant = account
      end
      
      # Reset tenant after each test
      teardown do
        ActsAsTenant.current_tenant = nil
      end
    end
    
    class ActionDispatch::IntegrationTest
      def sign_in_as(user, password: "password123")
        post sign_in_url, params: { email: user.email, password: password }
        assert_response :redirect
        user
      end
    
      def sign_out
        delete session_url(Current.session)
      end
    end
    
    class ActionController::TestCase
      # Ensure tenant is reset between controller tests
      teardown do
        ActsAsTenant.current_tenant = nil
      end
    end
    ```

### Phase 6: Update Model Tests

13. **Update User model tests for tenant scoping**
    
    File: `test/models/user_test.rb`
    
    Update the setup method:
    ```ruby
    require "test_helper"
    
    class UserTest < ActiveSupport::TestCase
      def setup
        @account = Account.create!(name: "Test Account", slug: "test-account-users")
        set_tenant(@account)  # Set tenant for scoping
      end
      
      # ... rest of tests remain the same
    end
    ```

14. **Update other model tests similarly**
    
    For each model test file, add to setup:
    - `test/models/advisor_test.rb`
    - `test/models/council_test.rb`
    - `test/models/conversation_test.rb`
    - `test/models/message_test.rb`
    - `test/models/usage_record_test.rb`
    - `test/models/council_advisor_test.rb`
    - `test/models/account_test.rb` (no tenant needed - it's the tenant root)
    
    Example pattern:
    ```ruby
    def setup
      @account = accounts(:one)
      set_tenant(@account)
    end
    ```

### Phase 7: Verify Controller Tests Work

15. **Controller tests should pass as-is** since tenant is set via authentication flow
    
    The `sign_in_as` helper already authenticates, which triggers `set_current_tenant` in ApplicationController.

### Phase 8: Manual Verification

16. **Verify tenant isolation in Rails console**
    ```ruby
    # Start console
    bin/rails console
    
    # Check that queries are scoped
    account1 = Account.first
    ActsAsTenant.current_tenant = account1
    
    # This should automatically add WHERE account_id = account1.id
    User.all.to_sql  # Check the SQL generated
    
    # Reset tenant
    ActsAsTenant.current_tenant = nil
    ```

## Verification

Run these commands to verify the implementation:

```bash
# 1. Verify gem installed
bundle list | grep acts_as_tenant

# 2. Run all model tests
bin/rails test test/models/

# 3. Run all controller tests
bin/rails test test/controllers/

# 4. Run system tests
bin/rails test test/system/

# 5. Run full test suite
bin/rails test
```

Expected outcomes:
- [ ] `acts_as_tenant` gem is in Gemfile.lock
- [ ] All model tests pass
- [ ] All controller tests pass
- [ ] All system tests pass
- [ ] Manual console test shows automatic scoping in SQL queries
- [ ] Creating records automatically assigns account_id
- [ ] Querying without explicit account_id scope returns only current tenant's data

## Doc impact

- **Update:** `.ai/docs/overview.md` - Change "acts_as_tenant (ready, not yet enabled)" to "acts_as_tenant (enabled)"
- **Create:** `.ai/docs/features/multi-tenancy.md` - Document how tenant scoping works, how to test with tenants, Current.account usage
- **Update:** `.ai/MEMORY.md` - Add acts_as_tenant commands and testing patterns

## Rollback

If needed, rollback the multi-tenancy activation:

1. **Remove gem from Gemfile**
   ```bash
   bundle remove acts_as_tenant
   ```

2. **Remove tenant methods from ApplicationController**
   - Remove `before_action :set_current_tenant`
   - Remove `set_current_tenant` method

3. **Remove acts_as_tenant from all models**
   - Replace `acts_as_tenant :account` with the original comment

4. **Remove account from Current attributes**
   - Remove `attribute :account` from Current

5. **Revert test_helper.rb changes**
   - Remove `set_tenant` helper
   - Remove teardown hooks

6. **Remove tenant setup from model tests**
   - Remove `set_tenant(@account)` from setup methods

---

**Approve this plan?**
