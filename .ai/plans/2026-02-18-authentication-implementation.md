# Plan: Authentication Implementation with authentication-zero

Date: 2026-02-18

## Goal

Implement a production-ready authentication system for Small Council using the `authentication-zero` gem, integrating with the existing multi-tenant Account/User model structure. This provides secure password-based authentication, email confirmations, password resets, and session management.

## Non-goals

- OAuth/Social login (can be added later via authentication-zero OAuth generators)
- Two-factor authentication (can be added later via authentication-zero 2FA generators)
- Passwordless authentication (can be added later)
- Custom UI styling (use default authentication-zero views, customize later)
- Authorization/policies (handled separately with action_policy)
- API token authentication (session-based only for this phase)

## Scope + assumptions

- Use `authentication-zero` gem (~> 4.0) - generates code, not a runtime dependency
- Integrate with existing `User` model (has `password_digest` column, `email`, `account_id`)
- Support multi-tenancy: user belongs_to account, account has_many users
- Signup flow creates both Account AND first User atomically
- Default mailer from: `noreply@smallcouncil.app` (update in production)
- Session cookie-based authentication (no JWT)
- Use existing `bcrypt` comment in Gemfile (uncomment it)

## Evidence from codebase inspection

- **User model** (`app/models/user.rb`): Has `password_digest` column ready, `has_secure_password` commented out
- **Account model** (`app/models/account.rb`): Has slug, name, ready for tenant root
- **Routes** (`config/routes.rb`): Empty except health check - needs auth routes
- **ApplicationController**: No authentication concern yet
- **Database**: `password_digest` already in schema, users have unique index on `[account_id, email]`
- **Tests**: Using Minitest, no controller tests exist yet

## Steps

### Phase 1: Gem Setup & Installation

1. **Uncomment bcrypt in Gemfile**
   ```ruby
   # In Gemfile, line 21
   gem "bcrypt", "~> 3.1.7"
   ```

2. **Add authentication-zero gem to development group**
   ```ruby
   group :development do
     gem "authentication-zero", "~> 4.0"
     # ... existing gems
   end
   ```

3. **Bundle install**
   ```bash
   bundle install
   ```

4. **Enable has_secure_password on User model**
   - File: `app/models/user.rb`
   - Uncomment `has_secure_password`
   - Remove password length validation if added by generator (auth-zero adds its own)

### Phase 2: Run authentication-zero Generators

5. **Run the authentication generator**
   ```bash
   bin/rails generate authentication
   ```
   
   This creates:
   - `app/controllers/sessions_controller.rb`
   - `app/controllers/passwords_controller.rb`
   - `app/controllers/password_resets_controller.rb`
   - `app/controllers/concerns/authentication.rb`
   - `app/controllers/concerns/set_current_request_details.rb`
   - `app/models/current.rb`
   - `app/models/session.rb`
   - `app/mailers/sessions_mailer.rb`
   - Views for sessions, passwords, password_resets
   - Database migrations for `sessions` table

6. **Verify generated files exist**
   ```bash
   ls -la app/controllers/sessions_controller.rb
   ls -la app/controllers/concerns/authentication.rb
   ls -la app/models/session.rb
   ```

### Phase 3: Database Migrations

7. **Review and run migrations**
   ```bash
   bin/rails db:migrate:status  # See pending migrations
   bin/rails db:migrate         # Create sessions table
   ```

8. **Verify sessions table created**
   - Check `db/schema.rb` has `create_table "sessions"`
   - Columns: `user_id`, `ip_address`, `user_agent`, `created_at`

### Phase 4: Model Integration

9. **Update User model for authentication**
   
   File: `app/models/user.rb`
   
   Changes needed:
   - Uncomment `has_secure_password`
   - Add associations for sessions
   - Add authentication-zero concerns if needed
   
   ```ruby
   class User < ApplicationRecord
     # acts_as_tenant :account will be enabled when gem is installed
     belongs_to :account
     
     # Authentication associations
     has_many :sessions, dependent: :destroy
     
     # Enable secure password (bcrypt)
     has_secure_password
     
     # ... rest of existing code
   end
   ```

10. **Configure Session model for multi-tenancy awareness**
    
    File: `app/models/session.rb` (created by generator)
    
    Ensure it works with our User model:
    ```ruby
    class Session < ApplicationRecord
      belongs_to :user
      
      # Delegate account access through user
      delegate :account, to: :user
      
      before_create do
        self.user_agent = Current.user_agent
        self.ip_address = Current.ip_address
      end
      
      def self.authenticate_by(token:)
        find_signed!(token, purpose: :session_token)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        raise ActiveRecord::RecordNotFound
      end
    end
    ```

### Phase 5: Controller Integration

11. **Add Authentication concern to ApplicationController**
    
    File: `app/controllers/application_controller.rb`
    
    ```ruby
    class ApplicationController < ActionController::Base
      include Authentication  # From authentication-zero
      
      # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
      allow_browser versions: :modern
      
      # Changes to the importmap will invalidate the etag for HTML responses
      stale_when_importmap_changes
    end
    ```

12. **Create RegistrationsController for Account+User signup**
    
    File: `app/controllers/registrations_controller.rb`
    
    Since we need to create both Account AND User atomically:
    
    ```ruby
    class RegistrationsController < ApplicationController
      allow_unauthenticated_access  # From Authentication concern
      
      def new
        @account = Account.new
        @account.users.build
      end
      
      def create
        @account = Account.new(account_params)
        
        # Set the first user as admin
        if @account.save
          user = @account.users.first
          user.update!(role: :admin)
          
          # Create session and log them in
          start_new_session_for(user)
          
          redirect_to root_path, notice: "Welcome to Small Council!"
        else
          render :new, status: :unprocessable_entity
        end
      end
      
      private
      
      def account_params
        params.require(:account).permit(
          :name, :slug,
          users_attributes: [:email, :password, :password_confirmation]
        )
      end
    end
    ```

### Phase 6: Routes Configuration

13. **Update routes with authentication routes**
    
    File: `config/routes.rb`
    
    ```ruby
    Rails.application.routes.draw do
      # Authentication routes
      resource :registration, only: [:new, :create]
      resource :session, only: [:new, :create, :destroy]
      resources :passwords, param: :token, only: [:new, :create, :edit, :update]
      resources :password_resets, only: [:new, :create]
      
      # App routes (protected)
      get "dashboard", to: "dashboard#index"
      resources :councils
      resources :conversations
      
      # Health check
      get "up" => "rails/health#show", as: :rails_health_check
      
      # Root
      root "sessions#new"
    end
    ```

### Phase 7: View Customization

14. **Create registration form view**
    
    File: `app/views/registrations/new.html.erb`
    
    ```erb
    <h1>Create your account</h1>
    
    <%= form_with model: @account, url: registration_path do |f| %>
      <% if @account.errors.any? %>
        <div class="error-messages">
          <h2><%= pluralize(@account.errors.count, "error") %> prohibited this account from being saved:</h2>
          <ul>
            <% @account.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>
      
      <div>
        <%= f.label :name, "Company/Organization Name" %>
        <%= f.text_field :name %>
      </div>
      
      <div>
        <%= f.label :slug, "URL Slug" %>
        <%= f.text_field :slug %>
        <small>Used for URLs: smallcouncil.app/<%= @account.slug || "your-slug" %></small>
      </div>
      
      <%= f.fields_for :users do |uf| %>
        <div>
          <%= uf.label :email %>
          <%= uf.email_field :email %>
        </div>
        
        <div>
          <%= uf.label :password %>
          <%= uf.password_field :password %>
        </div>
        
        <div>
          <%= uf.label :password_confirmation %>
          <%= uf.password_field :password_confirmation %>
        </div>
      <% end %>
      
      <%= f.submit "Create Account" %>
    <% end %>
    
    <p>Already have an account? <%= link_to "Sign in", new_session_path %></p>
    ```

15. **Update Account model to accept nested attributes**
    
    File: `app/models/account.rb`
    
    ```ruby
    class Account < ApplicationRecord
      has_many :users, dependent: :destroy
      # ... other associations
      
      accepts_nested_attributes_for :users, limit: 1  # Only first user during signup
      
      # ... rest of existing code
    end
    ```

### Phase 8: Mailer Configuration

16. **Configure mailer defaults**
    
    File: `app/mailers/application_mailer.rb`
    
    ```ruby
    class ApplicationMailer < ActionMailer::Base
      default from: "Small Council <noreply@smallcouncil.app>"
      layout "mailer"
    end
    ```

17. **Review SessionsMailer views**
    
    Check generated mailer views in:
    - `app/views/sessions_mailer/password_reset.html.erb`
    - `app/views/sessions_mailer/password_reset.text.erb`
    
    Ensure they reference correct app name "Small Council".

### Phase 9: Protected Routes Setup

18. **Create DashboardController as landing page**
    
    File: `app/controllers/dashboard_controller.rb`
    
    ```ruby
    class DashboardController < ApplicationController
      # Authentication concern provides require_authentication
      before_action :require_authentication
      
      def index
        @councils = Current.user.councils.recent
        @conversations = Current.user.conversations.recent
      end
    end
    ```

19. **Update existing controllers to require authentication**
    
    Controllers needing protection (create these protections):
    - `CouncilsController` - `before_action :require_authentication`
    - `ConversationsController` - `before_action :require_authentication`
    - `MessagesController` - `before_action :require_authentication`
    - `AdvisorsController` - `before_action :require_authentication`
    - `Settings::*Controllers` - `before_action :require_authentication`

### Phase 10: UI Integration

20. **Add navigation partial with auth links**
    
    File: `app/views/layouts/_navigation.html.erb`
    
    ```erb
    <nav>
      <% if authenticated? %>
        <span>Signed in as <%= Current.user.email %></span>
        <%= link_to "Dashboard", dashboard_path %>
        <%= button_to "Sign out", session_path, method: :delete %>
      <% else %>
        <%= link_to "Sign in", new_session_path %>
        <%= link_to "Create account", new_registration_path %>
      <% end %>
    </nav>
    ```

21. **Add navigation to application layout**
    
    File: `app/views/layouts/application.html.erb`
    
    Add before `<%= yield %>`:
    ```erb
    <body>
      <%= render "layouts/navigation" %>
      <%= yield %>
    </body>
    ```

22. **Add flash message display**
    
    In application layout or shared partial:
    ```erb
    <% if flash.any? %>
      <div class="flash-messages">
        <% flash.each do |type, message| %>
          <div class="flash <%= type %>"><%= message %></div>
        <% end %>
      </div>
    <% end %>
    ```

### Phase 11: Testing

23. **Add authentication test helper**
    
    File: `test/test_helper.rb`
    
    Add to `class ActionDispatch::IntegrationTest`:
    ```ruby
    class ActionDispatch::IntegrationTest
      def sign_in_as(user)
        post session_url, params: { 
          session: { 
            email: user.email, 
            password: user.password 
          } 
        }
        assert_response :redirect
      end
      
      def sign_out
        delete session_url
      end
    end
    ```

24. **Create authentication system test**
    
    File: `test/system/authentication_test.rb`
    
    ```ruby
    require "application_system_test_case"
    
    class AuthenticationTest < ApplicationSystemTestCase
      test "user can sign up" do
        visit new_registration_path
        
        fill_in "Company/Organization Name", with: "Test Co"
        fill_in "URL Slug", with: "test-co"
        fill_in "Email", with: "user@example.com"
        fill_in "Password", with: "password123"
        fill_in "Password confirmation", with: "password123"
        
        click_on "Create Account"
        
        assert_text "Welcome to Small Council!"
        assert_current_path dashboard_path
      end
      
      test "user can sign in" do
        account = accounts(:one)
        user = account.users.create!(email: "test@example.com", password: "password123", role: :member)
        
        visit new_session_path
        
        fill_in "Email", with: user.email
        fill_in "Password", with: "password123"
        click_on "Sign in"
        
        assert_text "Dashboard"
      end
      
      test "user can sign out" do
        account = accounts(:one)
        user = account.users.create!(email: "test@example.com", password: "password123", role: :member)
        
        sign_in_as(user)
        visit dashboard_path
        
        click_on "Sign out"
        
        assert_current_path new_session_path
      end
    end
    ```

25. **Add model tests for authentication**
    
    File: `test/models/user_test.rb`
    
    Add tests:
    ```ruby
    test "should have secure password" do
      user = User.new(email: "test@example.com", account: accounts(:one))
      user.password = "password123"
      assert user.save
      assert user.authenticate("password123")
      assert_not user.authenticate("wrongpassword")
    end
    
    test "should require password on create" do
      user = User.new(email: "test@example.com", account: accounts(:one))
      assert_not user.valid?
      assert_includes user.errors[:password], "can't be blank"
    end
    ```

26. **Run tests to verify**
    ```bash
    bin/rails test test/models/user_test.rb
    bin/rails test test/system/authentication_test.rb
    ```

### Phase 12: Development Environment Setup

27. **Configure development mailer (Letter Opener)**
    
    Add to Gemfile development group:
    ```ruby
    gem "letter_opener", "~> 1.10"
    ```
    
    Configure in `config/environments/development.rb`:
    ```ruby
    config.action_mailer.delivery_method = :letter_opener
    config.action_mailer.perform_deliveries = true
    ```

28. **Bundle and verify**
    ```bash
    bundle install
    ```

### Phase 13: Seeds and Fixtures Update

29. **Update seeds with authenticated users**
    
    File: `db/seeds.rb`
    
    ```ruby
    # Create demo account with user
    demo_account = Account.create!(
      name: "Demo Organization",
      slug: "demo"
    )
    
    demo_user = demo_account.users.create!(
      email: "demo@example.com",
      password: "password123",
      role: :admin
    )
    
    puts "Created demo account: #{demo_account.name}"
    puts "Demo user: #{demo_user.email} / password: password123"
    ```

30. **Update fixtures with password_digest**
    
    File: `test/fixtures/users.yml`
    
    ```yaml
    one:
      account: one
      email: user1@example.com
      password_digest: <%= BCrypt::Password.create("password123", cost: 4) %>
      role: member
      
    admin:
      account: one
      email: admin@example.com
      password_digest: <%= BCrypt::Password.create("password123", cost: 4) %>
      role: admin
    ```

## Verification

Run these commands to verify the implementation:

```bash
# 1. Verify migrations are applied
bin/rails db:migrate:status

# 2. Run model tests
bin/rails test test/models/user_test.rb

# 3. Run authentication system tests
bin/rails test test/system/authentication_test.rb

# 4. Verify routes are correct
bin/rails routes | grep -E "session|registration|password"

# 5. Manual test in browser (after rails server)
# - Visit http://localhost:3000/registrations/new
# - Create account
# - Check email in letter_opener
# - Sign in
# - Sign out
```

Expected outcomes:
- [ ] Sessions table exists in database
- [ ] User model has `has_secure_password` enabled
- [ ] Registration creates Account + User atomically
- [ ] Sessions controller creates session tokens
- [ ] Password reset emails sent via letter_opener in dev
- [ ] Protected routes redirect to sign in when not authenticated
- [ ] Current user accessible via `Current.user` and `Current.session`

## Doc impact

- **Create:** `.ai/docs/features/authentication.md` - Document authentication flow, Current attributes, session management
- **Update:** `.ai/MEMORY.md` - Add sign-in URLs, test credentials, common auth commands
- **Create:** `.ai/docs/features/multi-tenancy.md` - How auth integrates with tenant scoping

## Rollback

If needed, rollback authentication:

1. **Revert database changes:**
   ```bash
   bin/rails db:rollback STEP=1  # Remove sessions table
   ```

2. **Remove generated files:**
   ```bash
   rm -f app/controllers/sessions_controller.rb
   rm -f app/controllers/passwords_controller.rb
   rm -f app/controllers/password_resets_controller.rb
   rm -f app/controllers/registrations_controller.rb
   rm -rf app/controllers/concerns/authentication.rb
   rm -rf app/controllers/concerns/set_current_request_details.rb
   rm -f app/models/session.rb
   rm -f app/models/current.rb
   rm -f app/mailers/sessions_mailer.rb
   rm -rf app/views/sessions
   rm -rf app/views/passwords
   rm -rf app/views/password_resets
   rm -rf app/views/sessions_mailer
   rm -f app/views/registrations/new.html.erb
   rm -f app/views/layouts/_navigation.html.erb
   rm -rf test/mailers/sessions_mailer_test.rb
   ```

3. **Revert model changes:**
   - Comment out `has_secure_password` in User model
   - Remove `has_many :sessions` from User model
   - Remove `accepts_nested_attributes_for` from Account model

4. **Revert Gemfile changes:**
   - Remove `gem "authentication-zero"`
   - Comment out `gem "bcrypt"`
   - Remove `gem "letter_opener"` (if not needed elsewhere)

5. **Revert routes:**
   - Remove authentication routes from `config/routes.rb`

6. **Revert ApplicationController:**
   - Remove `include Authentication`

---

**Approve this plan?**
