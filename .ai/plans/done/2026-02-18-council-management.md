# Plan: Council CRUD with AI Advisor Members

Date: 2026-02-18

## Goal

Implement full CRUD for Councils and nested Advisors with a streamlined UI. This enables users to create councils (groups of AI advisors) and manage their advisors directly within each council.

**Architecture note:** The existing models use a many-to-many relationship (councils ↔ advisors via council_advisors join table) to support shared/global advisors. This plan **extends** the existing models to also support direct nested advisors while preserving the existing architecture.

## Non-goals

- Removing the existing many-to-many architecture (council_advisors join table stays)
- Changing advisor model fields (model_provider, model_id, global flags remain)
- AI conversation integration (messages/conversations already exist separately)
- Advanced authorization policies (RBAC, roles beyond creator check)
- API endpoints (HTML views only for this phase)
- Bulk advisor operations
- Council sharing/permissions management (visibility field exists, but UI for sharing is future work)

## Scope + assumptions

- Reuse existing Council and Advisor models (extend as needed)
- Nested advisor creation: advisors are created within a council context
- All advisors are account-scoped via acts_as_tenant
- Creator-only edit/destroy for councils (checked via `user_id`)
- All account users can view all account councils (tenant scoping handles this)
- UI uses Tailwind CSS + DaisyUI (existing setup)
- Testing with Minitest (existing setup)
- Authentication already in place (Current.user, Current.account)

## Evidence from codebase inspection

- **Council model** (`app/models/council.rb`): Has `name`, `description`, `account_id`, `user_id`, visibility enum, `acts_as_tenant :account`
- **Advisor model** (`app/models/advisor.rb`): Has `name`, `system_prompt`, `model_provider`, `model_id`, `account_id`, `global` flag, `acts_as_tenant :account`
- **CouncilAdvisor join** (`app/models/council_advisor.rb`): Links councils and advisors with `position` and `custom_prompt_override`
- **Routes** (`config/routes.rb`): Currently only has auth routes and dashboard, no council routes
- **Tests**: `test/models/council_test.rb` and `test/models/advisor_test.rb` exist with passing tests
- **UI**: Tailwind CSS + DaisyUI configured, navigation in `app/views/layouts/_navigation.html.erb`
- **Dashboard**: Shows councils list but "Create Council" button is disabled

## Steps

### Phase 1: Model Updates (Add Nested Advisor Support)

1. **Add optional belongs_to :council to Advisor model**
   
   File: `app/models/advisor.rb`
   
   Add to the model:
   ```ruby
   # For nested advisors (belongs to a specific council)
   belongs_to :council, optional: true
   
   # Update validations for nested advisors
   validates :model_provider, presence: true, unless: -> { council_id.present? }
   validates :model_id, presence: true, unless: -> { council_id.present? }
   ```

2. **Add migration for council_id on advisors**
   
   ```bash
   bin/rails generate migration AddCouncilIdToAdvisors council:references
   ```
   
   Migration will add `council_id` (nullable) to advisors table.

3. **Update Council model for nested advisors**
   
   File: `app/models/council.rb`
   
   Add association:
   ```ruby
   # Nested advisors (directly owned by this council)
   has_many :nested_advisors, class_name: "Advisor", dependent: :destroy
   ```

4. **Update CouncilAdvisor model (join table) documentation**
   
   File: `app/models/council_advisor.rb`
   
   Add comment clarifying purpose:
   ```ruby
   # CouncilAdvisor links shared/global advisors to councils
   # For nested (council-specific) advisors, use council.nested_advisors
   ```

5. **Run migration**
   ```bash
   bin/rails db:migrate
   ```

### Phase 2: Routes Configuration

6. **Add council and nested advisor routes**
   
   File: `config/routes.rb`
   
   Update the protected app routes section:
   ```ruby
   # Protected app routes
   get "dashboard", to: "dashboard#index"
   
   resources :councils do
     resources :advisors, only: [:new, :create, :edit, :update, :destroy], controller: "council_advisors"
   end
   
   # Future: Shared advisors management (optional)
   # resources :advisors, only: [:index, :show, :new, :create, :edit, :update, :destroy]
   ```

7. **Verify routes**
   ```bash
   bin/rails routes | grep council
   ```
   Expected output shows:
   - GET /councils (index)
   - GET /councils/:id (show)
   - GET /councils/new (new)
   - POST /councils (create)
   - GET /councils/:id/edit (edit)
   - PATCH/PUT /councils/:id (update)
   - DELETE /councils/:id (destroy)
   - Nested: /councils/:council_id/advisors/*

### Phase 3: CouncilsController

8. **Create CouncilsController with all CRUD actions**
   
   File: `app/controllers/councils_controller.rb`
   
   ```ruby
   class CouncilsController < ApplicationController
     before_action :set_council, only: [:show, :edit, :update, :destroy]
     before_action :require_creator, only: [:edit, :update, :destroy]
     
     def index
       @councils = Current.account.councils.order(created_at: :desc)
     end
     
     def show
       @advisors = @council.nested_advisors.order(created_at: :asc)
     end
     
     def new
       @council = Current.account.councils.new
     end
     
     def create
       @council = Current.account.councils.new(council_params)
       @council.user = Current.user
       
       if @council.save
         redirect_to @council, notice: "Council created successfully."
       else
         render :new, status: :unprocessable_entity
       end
     end
     
     def edit
     end
     
     def update
       if @council.update(council_params)
         redirect_to @council, notice: "Council updated successfully."
       else
         render :edit, status: :unprocessable_entity
       end
     end
     
     def destroy
       @council.destroy
       redirect_to councils_url, notice: "Council deleted successfully."
     end
     
     private
     
     def set_council
       @council = Current.account.councils.find(params[:id])
     end
     
     def require_creator
       unless @council.user_id == Current.user.id
         redirect_to councils_url, alert: "Only the creator can modify this council."
       end
     end
     
     def council_params
       params.require(:council).permit(:name, :description, :visibility)
     end
   end
   ```

### Phase 4: CouncilAdvisorsController (Nested Advisors)

9. **Create CouncilAdvisorsController for nested advisor management**
   
   File: `app/controllers/council_advisors_controller.rb`
   
   ```ruby
   class CouncilAdvisorsController < ApplicationController
     before_action :set_council
     before_action :set_advisor, only: [:edit, :update, :destroy]
     before_action :require_creator
     
     def new
       @advisor = @council.nested_advisors.new
     end
     
     def create
       @advisor = @council.nested_advisors.new(advisor_params)
       @advisor.account = Current.account
       
       # Set defaults for nested advisors (simplified model)
       @advisor.model_provider ||= "openai"
       @advisor.model_id ||= "gpt-4"
       @advisor.global = false
       
       if @advisor.save
         # Also add to council_advisors join table for consistency
         @council.council_advisors.find_or_create_by!(advisor: @advisor) do |ca|
           ca.position = @council.council_advisors.count
         end
         
         redirect_to @council, notice: "Advisor added successfully."
       else
         render :new, status: :unprocessable_entity
       end
     end
     
     def edit
     end
     
     def update
       if @advisor.update(advisor_params)
         redirect_to @council, notice: "Advisor updated successfully."
       else
         render :edit, status: :unprocessable_entity
       end
     end
     
     def destroy
       @advisor.destroy
       redirect_to @council, notice: "Advisor removed successfully."
     end
     
     private
     
     def set_council
       @council = Current.account.councils.find(params[:council_id])
     end
     
     def set_advisor
       @advisor = @council.nested_advisors.find(params[:id])
     end
     
     def require_creator
       unless @council.user_id == Current.user.id
         redirect_to @council, alert: "Only the creator can manage advisors."
       end
     end
     
     def advisor_params
       params.require(:advisor).permit(:name, :short_description, :system_prompt)
     end
   end
   ```

### Phase 5: Views - Councils Index

10. **Create councils index view**
    
    File: `app/views/councils/index.html.erb`
    
    ```erb
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-3xl font-bold">Councils</h1>
        <%= link_to "New Council", new_council_path, class: "btn btn-primary" %>
      </div>

      <% if @councils.any? %>
        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <% @councils.each do |council| %>
            <div class="card bg-base-100 shadow hover:shadow-lg transition-shadow">
              <div class="card-body">
                <h2 class="card-title"><%= council.name %></h2>
                <p class="text-sm text-base-content/70 line-clamp-2">
                  <%= council.description.presence || "No description" %>
                </p>
                
                <div class="flex items-center gap-2 mt-2">
                  <span class="badge badge-<%= council.visibility_shared? ? 'secondary' : 'ghost' %>">
                    <%= council.visibility %>
                  </span>
                  <span class="text-xs text-base-content/50">
                    <%= pluralize(council.nested_advisors.count + council.advisors.count, "advisor") %>
                  </span>
                </div>
                
                <div class="card-actions justify-end mt-4">
                  <%= link_to "View", council, class: "btn btn-sm btn-ghost" %>
                  <% if council.user_id == Current.user.id %>
                    <%= link_to "Edit", edit_council_path(council), class: "btn btn-sm btn-ghost" %>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-12">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-20 w-20 mx-auto text-base-content/30 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <h3 class="text-xl font-semibold mb-2">No councils yet</h3>
          <p class="text-base-content/60 mb-4">Create your first council to start collaborating with AI advisors.</p>
          <%= link_to "Create Council", new_council_path, class: "btn btn-primary" %>
        </div>
      <% end %>
    </div>
    ```

### Phase 6: Views - Council Show

11. **Create council show view with advisors list**
    
    File: `app/views/councils/show.html.erb`
    
    ```erb
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-start justify-between">
        <div>
          <div class="flex items-center gap-2 mb-1">
            <h1 class="text-3xl font-bold"><%= @council.name %></h1>
            <span class="badge badge-<%= @council.visibility_shared? ? 'secondary' : 'ghost' %>">
              <%= @council.visibility %>
            </span>
          </div>
          <p class="text-base-content/70"><%= @council.description.presence || "No description" %></p>
          <p class="text-sm text-base-content/50 mt-1">
            Created by <%= @council.user.email %> · <%= time_ago_in_words(@council.created_at) %> ago
          </p>
        </div>
        
        <div class="flex gap-2">
          <% if @council.user_id == Current.user.id %>
            <%= link_to "Edit Council", edit_council_path(@council), class: "btn btn-ghost btn-sm" %>
            <%= button_to "Delete", @council, method: :delete, 
                class: "btn btn-error btn-sm", 
                data: { turbo_confirm: "Are you sure? This will delete the council and all its advisors." } %>
          <% end %>
        </div>
      </div>

      <!-- Advisors Section -->
      <section class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h2 class="card-title">Advisors</h2>
            <% if @council.user_id == Current.user.id %>
              <%= link_to "Add Advisor", new_council_advisor_path(@council), class: "btn btn-primary btn-sm" %>
            <% end %>
          </div>

          <% if @advisors.any? %>
            <div class="grid gap-4 md:grid-cols-2">
              <% @advisors.each do |advisor| %>
                <div class="card bg-base-200">
                  <div class="card-body p-4">
                    <h3 class="font-semibold"><%= advisor.name %></h3>
                    <p class="text-sm text-base-content/70 line-clamp-2">
                      <%= advisor.system_prompt.truncate(100) %>
                    </p>
                    
                    <% if @council.user_id == Current.user.id %>
                      <div class="card-actions justify-end mt-2">
                        <%= link_to "Edit", edit_council_advisor_path(@council, advisor), class: "btn btn-xs btn-ghost" %>
                        <%= button_to "Remove", council_advisor_path(@council, advisor), 
                            method: :delete,
                            class: "btn btn-xs btn-ghost text-error",
                            data: { turbo_confirm: "Remove this advisor?" } %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="text-center py-8">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-16 w-16 mx-auto text-base-content/30 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              <p class="text-base-content/60 mb-4">No advisors in this council yet.</p>
              <% if @council.user_id == Current.user.id %>
                <%= link_to "Add First Advisor", new_council_advisor_path(@council), class: "btn btn-primary" %>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>

      <!-- Back link -->
      <%= link_to "← Back to Councils", councils_path, class: "btn btn-ghost" %>
    </div>
    ```

### Phase 7: Views - Council Form (New/Edit)

12. **Create shared council form partial**
    
    File: `app/views/councils/_form.html.erb`
    
    ```erb
    <%= form_with model: council, class: "space-y-4" do |f| %>
      <% if council.errors.any? %>
        <div class="alert alert-error">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 shrink-0 stroke-current" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <h3 class="font-bold"><%= pluralize(council.errors.count, "error") %> prohibited this council from being saved:</h3>
            <ul class="mt-1 list-disc list-inside text-sm">
              <% council.errors.full_messages.each do |message| %>
                <li><%= message %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div class="form-control">
        <%= f.label :name, class: "label" %>
        <%= f.text_field :name, class: "input input-bordered", placeholder: "e.g., Engineering Leadership Council" %>
      </div>

      <div class="form-control">
        <%= f.label :description, class: "label" %>
        <%= f.text_area :description, class: "textarea textarea-bordered", rows: 3, placeholder: "Optional: What is this council for?" %>
      </div>

      <div class="form-control">
        <%= f.label :visibility, class: "label" %>
        <div class="flex gap-4">
          <label class="label cursor-pointer gap-2">
            <%= f.radio_button :visibility, "private", class: "radio" %>
            <span class="label-text">Private (only you)</span>
          </label>
          <label class="label cursor-pointer gap-2">
            <%= f.radio_button :visibility, "shared", class: "radio" %>
            <span class="label-text">Shared (account members)</span>
          </label>
        </div>
      </div>

      <div class="card-actions justify-end mt-6">
        <%= link_to "Cancel", councils_path, class: "btn btn-ghost" %>
        <%= f.submit class: "btn btn-primary" %>
      </div>
    <% end %>
    ```

13. **Create new council view**
    
    File: `app/views/councils/new.html.erb`
    
    ```erb
    <div class="max-w-2xl mx-auto">
      <h1 class="text-3xl font-bold mb-6">New Council</h1>
      
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <%= render "form", council: @council %>
        </div>
      </div>
    </div>
    ```

14. **Create edit council view**
    
    File: `app/views/councils/edit.html.erb`
    
    ```erb
    <div class="max-w-2xl mx-auto">
      <h1 class="text-3xl font-bold mb-6">Edit Council</h1>
      
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <%= render "form", council: @council %>
        </div>
      </div>
    </div>
    ```

### Phase 8: Views - Advisor Forms (Nested)

15. **Create shared advisor form partial**
    
    File: `app/views/council_advisors/_form.html.erb`
    
    ```erb
    <%= form_with model: [@council, advisor], url: url, method: method, class: "space-y-4" do |f| %>
      <% if advisor.errors.any? %>
        <div class="alert alert-error">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 shrink-0 stroke-current" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <h3 class="font-bold"><%= pluralize(advisor.errors.count, "error") %> prohibited this advisor from being saved:</h3>
            <ul class="mt-1 list-disc list-inside text-sm">
              <% advisor.errors.full_messages.each do |message| %>
                <li><%= message %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div class="form-control">
        <%= f.label :name, "Advisor Name", class: "label" %>
        <%= f.text_field :name, class: "input input-bordered", placeholder: "e.g., Strategic Advisor" %>
      </div>

      <div class="form-control">
        <%= f.label :system_prompt, "Prompt / Instructions", class: "label" %>
        <%= f.text_area :system_prompt, class: "textarea textarea-bordered", rows: 6, 
            placeholder: "Describe this advisor's role, expertise, and how they should respond..." %>
        <label class="label">
          <span class="label-text-alt text-base-content/60">
            This is the system prompt that guides the AI's behavior.
          </span>
        </label>
      </div>

      <div class="card-actions justify-end mt-6">
        <%= link_to "Cancel", @council, class: "btn btn-ghost" %>
        <%= f.submit class: "btn btn-primary" %>
      </div>
    <% end %>
    ```

16. **Create new advisor view (nested)**
    
    File: `app/views/council_advisors/new.html.erb`
    
    ```erb
    <div class="max-w-2xl mx-auto">
      <div class="mb-6">
        <%= link_to "← Back to #{@council.name}", @council, class: "text-sm text-base-content/60 hover:text-base-content" %>
        <h1 class="text-3xl font-bold mt-2">Add Advisor</h1>
        <p class="text-base-content/70">Add a new AI advisor to <%= @council.name %></p>
      </div>
      
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <%= render "form", council: @council, advisor: @advisor, url: council_advisors_path(@council), method: :post %>
        </div>
      </div>
    </div>
    ```

17. **Create edit advisor view (nested)**
    
    File: `app/views/council_advisors/edit.html.erb`
    
    ```erb
    <div class="max-w-2xl mx-auto">
      <div class="mb-6">
        <%= link_to "← Back to #{@council.name}", @council, class: "text-sm text-base-content/60 hover:text-base-content" %>
        <h1 class="text-3xl font-bold mt-2">Edit Advisor</h1>
        <p class="text-base-content/70">Update <%= @advisor.name %> in <%= @council.name %></p>
      </div>
      
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <%= render "form", council: @council, advisor: @advisor, url: council_advisor_path(@council, @advisor), method: :patch %>
        </div>
      </div>
    </div>
    ```

### Phase 9: Navigation Updates

18. **Add Councils link to navigation**
    
    File: `app/views/layouts/_navigation.html.erb`
    
    Update the navbar-center section:
    ```erb
    <div class="navbar-center hidden lg:flex">
      <% if authenticated? %>
        <ul class="menu menu-horizontal px-1">
          <li><%= link_to "Dashboard", dashboard_path %></li>
          <li><%= link_to "Councils", councils_path %></li>
          <li><%= link_to "Sessions", sessions_path %></li>
        </ul>
      <% end %>
    </div>
    ```

19. **Add mobile navigation for Councils**
    
    Update the mobile navigation section:
    ```erb
    <!-- Mobile navigation -->
    <div class="lg:hidden navbar bg-base-200 border-t border-base-300">
      <div class="flex-1 flex justify-center">
        <%= link_to dashboard_path, class: "btn btn-ghost flex-1 rounded-none" do %>
          <!-- Dashboard icon -->
        <% end %>
        <%= link_to councils_path, class: "btn btn-ghost flex-1 rounded-none" do %>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
        <% end %>
        <%= link_to sessions_path, class: "btn btn-ghost flex-1 rounded-none" do %>
          <!-- Sessions icon -->
        <% end %>
      </div>
    </div>
    ```

### Phase 10: Dashboard Update

20. **Enable "Create Council" button in dashboard**
    
    File: `app/views/dashboard/index.html.erb`
    
    Replace the disabled button:
    ```erb
    <!-- Change from: -->
    <button class="btn btn-primary btn-disabled">Create Council</button>
    
    <!-- To: -->
    <%= link_to "Create Council", new_council_path, class: "btn btn-primary" %>
    ```

### Phase 11: Model Tests

21. **Update Council model tests for nested_advisors**
    
    File: `test/models/council_test.rb`
    
    Add tests:
    ```ruby
    test "has many nested_advisors association" do
      council = Council.new
      assert_respond_to council, :nested_advisors
    end
    
    test "dependent destroy removes nested_advisors" do
      council = @account.councils.create!(name: "Test Council", user: @user)
      council.nested_advisors.create!(
        name: "Nested Advisor",
        system_prompt: "You are a test",
        model_provider: "openai",
        model_id: "gpt-4",
        account: @account
      )
      assert_difference("Advisor.count", -1) do
        council.destroy
      end
    end
    ```

22. **Update Advisor model tests for council association**
    
    File: `test/models/advisor_test.rb`
    
    Add tests:
    ```ruby
    test "belongs to council (optional)" do
      advisor = Advisor.new
      assert_respond_to advisor, :council
    end
    
    test "valid with council_id (nested advisor)" do
      user = @account.users.create!(email: "test@example.com", password: "password123")
      council = @account.councils.create!(name: "Test Council", user: user)
      
      advisor = @account.advisors.new(
        name: "Nested Advisor",
        system_prompt: "You are nested",
        council: council
      )
      # Should be valid even without model_provider/model_id for nested advisors
      # (requires validation update as per Phase 1)
    end
    ```

### Phase 12: Controller Tests

23. **Create CouncilsController test**
    
    File: `test/controllers/councils_controller_test.rb`
    
    ```ruby
    require "test_helper"

    class CouncilsControllerTest < ActionDispatch::IntegrationTest
      def setup
        @account = accounts(:one)
        host! "test.example.com"
        sign_in_as(users(:one))
        set_tenant(@account)
      end

      test "should get index" do
        get councils_url
        assert_response :success
      end

      test "should get new" do
        get new_council_url
        assert_response :success
      end

      test "should create council" do
        assert_difference("Council.count") do
          post councils_url, params: { council: { name: "Test Council", description: "A test council" } }
        end
        assert_redirected_to council_url(Council.last)
      end

      test "should show council" do
        council = @account.councils.create!(name: "Test", user: users(:one))
        get council_url(council)
        assert_response :success
      end

      test "should get edit for creator" do
        council = @account.councils.create!(name: "Test", user: users(:one))
        get edit_council_url(council)
        assert_response :success
      end

      test "should not get edit for non-creator" do
        other_user = @account.users.create!(email: "other@example.com", password: "password123")
        council = @account.councils.create!(name: "Test", user: other_user)
        get edit_council_url(council)
        assert_redirected_to councils_url
      end

      test "should update council for creator" do
        council = @account.councils.create!(name: "Test", user: users(:one))
        patch council_url(council), params: { council: { name: "Updated Name" } }
        assert_redirected_to council_url(council)
        assert_equal "Updated Name", council.reload.name
      end

      test "should destroy council for creator" do
        council = @account.councils.create!(name: "Test", user: users(:one))
        assert_difference("Council.count", -1) do
          delete council_url(council)
        end
        assert_redirected_to councils_url
      end
    end
    ```

24. **Create CouncilAdvisorsController test**
    
    File: `test/controllers/council_advisors_controller_test.rb`
    
    ```ruby
    require "test_helper"

    class CouncilAdvisorsControllerTest < ActionDispatch::IntegrationTest
      def setup
        @account = accounts(:one)
        host! "test.example.com"
        sign_in_as(users(:one))
        set_tenant(@account)
        @council = @account.councils.create!(name: "Test Council", user: users(:one))
      end

      test "should get new" do
        get new_council_advisor_url(@council)
        assert_response :success
      end

      test "should create advisor" do
        assert_difference("Advisor.count") do
          post council_advisors_url(@council), params: { 
            advisor: { name: "Test Advisor", system_prompt: "You are helpful" } 
          }
        end
        assert_redirected_to council_url(@council)
      end

      test "should get edit for creator" do
        advisor = @council.nested_advisors.create!(
          name: "Test",
          system_prompt: "Test prompt",
          account: @account,
          model_provider: "openai",
          model_id: "gpt-4"
        )
        get edit_council_advisor_url(@council, advisor)
        assert_response :success
      end

      test "should update advisor for creator" do
        advisor = @council.nested_advisors.create!(
          name: "Test",
          system_prompt: "Test prompt",
          account: @account,
          model_provider: "openai",
          model_id: "gpt-4"
        )
        patch council_advisor_url(@council, advisor), params: { 
          advisor: { name: "Updated Name" } 
        }
        assert_redirected_to council_url(@council)
      end

      test "should destroy advisor for creator" do
        advisor = @council.nested_advisors.create!(
          name: "Test",
          system_prompt: "Test prompt",
          account: @account,
          model_provider: "openai",
          model_id: "gpt-4"
        )
        assert_difference("Advisor.count", -1) do
          delete council_advisor_url(@council, advisor)
        end
        assert_redirected_to council_url(@council)
      end
    end
    ```

### Phase 13: Integration/System Tests

25. **Create councils system test**
    
    File: `test/system/councils_test.rb`
    
    ```ruby
    require "application_system_test_case"

    class CouncilsTest < ApplicationSystemTestCase
      def setup
        @account = accounts(:one)
        @user = users(:one)
        sign_in_as(@user)
        set_tenant(@account)
      end

      test "visiting the councils index" do
        visit councils_url
        assert_selector "h1", text: "Councils"
      end

      test "creating a council" do
        visit councils_url
        click_on "New Council"
        
        fill_in "Name", with: "Engineering Council"
        fill_in "Description", with: "For discussing technical decisions"
        click_on "Create Council"
        
        assert_text "Council created successfully"
        assert_text "Engineering Council"
      end

      test "viewing a council with advisors" do
        council = @account.councils.create!(name: "Test Council", user: @user)
        visit council_url(council)
        
        assert_selector "h1", text: "Test Council"
        assert_text "No advisors in this council yet"
      end

      test "adding an advisor to a council" do
        council = @account.councils.create!(name: "Test Council", user: @user)
        visit council_url(council)
        
        click_on "Add First Advisor"
        fill_in "Advisor Name", with: "Strategic Advisor"
        fill_in "Prompt / Instructions", with: "You are a strategic advisor"
        click_on "Create Advisor"
        
        assert_text "Advisor added successfully"
        assert_text "Strategic Advisor"
      end

      test "editing an advisor" do
        council = @account.councils.create!(name: "Test Council", user: @user)
        advisor = council.nested_advisors.create!(
          name: "Old Name",
          system_prompt: "Old prompt",
          account: @account,
          model_provider: "openai",
          model_id: "gpt-4"
        )
        visit council_url(council)
        
        click_on "Edit"
        fill_in "Advisor Name", with: "New Name"
        click_on "Update Advisor"
        
        assert_text "Advisor updated successfully"
        assert_text "New Name"
      end

      test "deleting an advisor" do
        council = @account.councils.create!(name: "Test Council", user: @user)
        advisor = council.nested_advisors.create!(
          name: "To Delete",
          system_prompt: "Prompt",
          account: @account,
          model_provider: "openai",
          model_id: "gpt-4"
        )
        visit council_url(council)
        
        accept_confirm do
          click_on "Remove"
        end
        
        assert_text "Advisor removed successfully"
        assert_no_text "To Delete"
      end

      test "only creator can edit council" do
        other_user = @account.users.create!(email: "other@example.com", password: "password123")
        council = @account.councils.create!(name: "Protected Council", user: other_user)
        
        visit council_url(council)
        assert_no_selector "a", text: "Edit Council"
        assert_no_selector "button", text: "Delete"
      end
    end
    ```

### Phase 14: String Extension for Truncate

26. **Add truncate method to String (if not already available)**
    
    File: `config/initializers/string_extensions.rb`
    
    ```ruby
    class String
      def truncate(n)
        length > n ? "#{self[0...n]}..." : self
      end
    end
    ```

## Verification

Run these commands to verify the implementation:

```bash
# 1. Verify migrations are applied
bin/rails db:migrate:status

# 2. Run model tests
bin/rails test test/models/council_test.rb test/models/advisor_test.rb

# 3. Run controller tests
bin/rails test test/controllers/councils_controller_test.rb
bin/rails test test/controllers/council_advisors_controller_test.rb

# 4. Run system tests
bin/rails test test/system/councils_test.rb

# 5. Verify routes are correct
bin/rails routes | grep council

# 6. Manual test in browser (after rails server)
# - Visit http://localhost:3000/councils
# - Create a council
# - Add advisors to the council
# - Edit council and advisors
# - Delete advisors
# - Delete council
```

Expected outcomes:
- [ ] Councils index page lists all account councils
- [ ] Council show page displays advisors
- [ ] Council CRUD works (create, read, update, delete)
- [ ] Advisor CRUD works (create, read, update, delete) within council context
- [ ] Navigation shows "Councils" link
- [ ] Dashboard "Create Council" button works
- [ ] Only creator can edit/destroy council and advisors
- [ ] Tenant scoping prevents cross-account access
- [ ] All tests pass

## Doc impact

- **Create:** `.ai/docs/features/council-management.md` - Document council and advisor management flow
- **Update:** `.ai/MEMORY.md` - Add council/advisor URLs and quick reference
- **Create:** `.ai/docs/features/nested-advisors.md` - Explain nested vs shared advisor architecture
- **Update:** `.ai/docs/overview.md` - Update if needed with new controller paths

## Rollback

If needed, rollback the implementation:

1. **Remove controllers:**
   ```bash
   rm -f app/controllers/councils_controller.rb
   rm -f app/controllers/council_advisors_controller.rb
   ```

2. **Remove views:**
   ```bash
   rm -rf app/views/councils
   rm -rf app/views/council_advisors
   ```

3. **Revert routes** (remove council resources from `config/routes.rb`)

4. **Rollback database** (optional):
   ```bash
   bin/rails db:rollback STEP=1  # Removes council_id from advisors
   ```

5. **Revert model changes** (remove `belongs_to :council, optional: true` and `has_many :nested_advisors`)

6. **Remove tests:**
   ```bash
   rm -f test/controllers/councils_controller_test.rb
   rm -f test/controllers/council_advisors_controller_test.rb
   rm -f test/system/councils_test.rb
   ```

---

**Approve this plan?**
