require "test_helper"

# Critical Security Tests
# These tests verify the application's security boundaries and authorization controls.

class SecurityControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
  end

  # ============================================================================
  # PARAMETER TAMPERING TESTS - Critical Priority
  # ============================================================================

  test "cannot create council in another account via account_id parameter" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create another account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Account", slug: "other-account-tamper-test")
    end

    assert_difference("Council.count") do
      post councils_url, params: {
        council: {
          name: "Test Council",
          description: "Attempting to set account_id",
          account_id: other_account.id
        }
      }
    end

    council = Council.last
    # Should be assigned to current user's account, not the tampered account_id
    assert_equal @account.id, council.account_id
    refute_equal other_account.id, council.account_id
  end

  test "cannot create council in another space via space_id parameter" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create another space in the same account
    other_space = @account.spaces.create!(name: "Other Space")

    # Get the current space (where the POST is being made)
    current_space = @space

    assert_difference("Council.count") do
      post space_councils_url(current_space), params: {
        council: {
          name: "Test Council",
          description: "Attempting to set space_id",
          space_id: other_space.id  # Trying to create in other space
        }
      }
    end

    council = Council.last
    # Council should be in the space where the POST was made
    assert_equal current_space.id, council.space_id
  end

  test "cannot create conversation in another council via council_id parameter" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create another council in the same space
    other_council = @account.councils.create!(
      name: "Other Council",
      user: @user,
      space: @space
    )

    # Create the primary council for the POST
    primary_council = @account.councils.create!(
      name: "Primary Council",
      user: @user,
      space: @space
    )

    assert_difference("Conversation.count") do
      post council_conversations_url(primary_council), params: {
        conversation: {
          title: "Test Conversation",
          council_id: other_council.id  # Attempting to assign to different council
        }
      }
    end

    conversation = Conversation.last
    # Conversation should be in the council from the URL, not the tampered council_id
    assert_equal primary_council.id, conversation.council_id
  end

  test "cannot assign another user as conversation creator via user_id parameter" do
    sign_in_as(@user)
    set_tenant(@account)

    other_user = @account.users.create!(
      email: "other@example.com",
      password: "password123"
    )

    council = @account.councils.create!(
      name: "Test Council",
      user: @user,
      space: @space
    )

    assert_difference("Conversation.count") do
      post council_conversations_url(council), params: {
        conversation: {
          title: "Test Conversation",
          user_id: other_user.id  # Attempting to set different user
        }
      }
    end

    conversation = Conversation.last
    # Current user should be the creator, not the tampered user_id
    assert_equal @user.id, conversation.user_id
    refute_equal other_user.id, conversation.user_id
  end

  # ============================================================================
  # CROSS-ACCOUNT ACCESS TESTS - Critical Priority
  # ============================================================================

  test "cannot access messages from another account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create resources in other account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Messages", slug: "other-messages")
    end
    other_user = ActsAsTenant.without_tenant do
      other_account.users.create!(email: "other@example.com", password: "password123")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Space")
    end
    other_council = ActsAsTenant.without_tenant do
      other_account.councils.create!(name: "Other Council", user: other_user, space: other_space)
    end
    other_conversation = ActsAsTenant.without_tenant do
      other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conv", space: other_space)
    end
    ActsAsTenant.without_tenant do
      other_account.messages.create!(
        conversation: other_conversation,
        sender: other_user,
        role: "user",
        content: "Secret message"
      )
    end

    # Try to access the other account's conversation - should be 404
    get conversation_url(other_conversation)
    assert_response :not_found
  end

  test "cannot use llm_model from another account when creating advisor" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create resources in other account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Advisors", slug: "other-advisors-test")
    end
    other_provider = ActsAsTenant.without_tenant do
      other_account.providers.create!(name: "Other Provider", provider_type: "openai", api_key: "key")
    end
    other_model = ActsAsTenant.without_tenant do
      other_provider.llm_models.create!(account: other_account, name: "GPT-4", identifier: "gpt-4")
    end

    # Try to create advisor with other account's model
    assert_no_difference("Advisor.count") do
      post space_advisors_url(@space), params: {
        advisor: {
          name: "Tampered Advisor",
          system_prompt: "Test",
          llm_model_id: other_model.id  # Trying to use other account's model
        }
      }
    end

    # The controller should reject the foreign llm_model_id
    # Advisor creation should fail because no valid llm_model is provided
    assert_response :unprocessable_entity
    assert_nil Advisor.find_by(name: "Tampered Advisor"), "Advisor should not be created with foreign model"
  end

  test "cannot access providers from another account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create provider in other account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Provider", slug: "other-provider-test")
    end
    other_provider = ActsAsTenant.without_tenant do
      other_account.providers.create!(name: "Other Provider", provider_type: "openai", api_key: "secret")
    end

    # Try to access other account's provider edit page
    # The provider ID from another account won't be found in Current.account.providers
    get edit_provider_url(other_provider)
    # Should get 404 since the provider isn't in Current.account
    assert_response :not_found
  end

  test "cannot update provider from another account" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Provider", slug: "other-provider-update-test")
    end
    other_provider = ActsAsTenant.without_tenant do
      other_account.providers.create!(name: "Other Provider", provider_type: "openai", api_key: "secret")
    end

    # Try to update other account's provider
    # The provider won't be found in Current.account.providers scope
    patch provider_url(other_provider), params: {
      provider: { name: "Hacked Name" }
    }

    # Should get 404
    assert_response :not_found

    # Verify name wasn't changed
    ActsAsTenant.without_tenant do
      assert_equal "Other Provider", other_provider.reload.name
    end
  end

  # ============================================================================
  # NESTED RESOURCE AUTHORIZATION TESTS - High Priority
  # ============================================================================

  test "cannot create message in conversation from different space" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create another space and conversation
    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(name: "Other Council", user: @user, space: other_space)
    other_conversation = @account.conversations.create!(
      council: other_council,
      user: @user,
      title: "Other Space Conv",
      space: other_space
    )

    # Try to post to conversation in other space while Current.space is @space
    # The MessagesController now enforces space authorization
    assert_no_difference "Message.count" do
      post conversation_messages_url(other_conversation), params: {
        message: { content: "Test message in other space" }
      }
    end

    # Should be redirected with alert
    assert_redirected_to conversations_path
    assert_equal "You can only post to conversations in your current space.", flash[:alert]
  end

  # ============================================================================
  # CROSS-SPACE WITHIN SAME ACCOUNT TESTS - Medium Priority
  # ============================================================================

  test "can access spaces within same account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create multiple spaces
    space1 = @account.spaces.create!(name: "Space 1")
    space2 = @account.spaces.create!(name: "Space 2")

    # Should be able to access both
    get space_url(space1)
    assert_redirected_to space_councils_path(space1)

    get space_url(space2)
    assert_redirected_to space_councils_path(space2)
  end

  test "space switching works correctly" do
    sign_in_as(@user)
    set_tenant(@account)

    space1 = @account.spaces.create!(name: "First Space")
    space2 = @account.spaces.create!(name: "Second Space")

    # Switch to space1
    get space_url(space1)
    assert_equal space1.id, session[:space_id]

    # Switch to space2
    get space_url(space2)
    assert_equal space2.id, session[:space_id]
  end

  # ============================================================================
  # EDGE CASES AND BOUNDARY TESTS - Medium Priority
  # ============================================================================

  test "cannot access resource with invalid ID format" do
    sign_in_as(@user)
    set_tenant(@account)

    # Try various invalid ID formats
    # Rails will either raise RecordNotFound or handle gracefully
    get council_url(id: "invalid")
    # Response can be 404 or handled by Rails
    assert_response :not_found
  end

  test "strong parameters reject unexpected fields" do
    sign_in_as(@user)
    set_tenant(@account)

    # Try to pass extra parameters that aren't permitted
    assert_difference("Council.count") do
      post councils_url, params: {
        council: {
          name: "Test Council",
          description: "Test",
          created_at: 1.year.ago,  # Should be rejected
          updated_at: 1.year.ago,  # Should be rejected
          id: 99999,  # Should be rejected
          user_id: 1  # Should be rejected
        }
      }
    end

    council = Council.last
    assert_equal @user.id, council.user_id  # Should be current user, not 99999
    assert council.created_at > 1.minute.ago  # Should be recent, not 1 year ago
  end

  test "deactivated account access is blocked" do
    # This test assumes accounts can be deactivated
    # If not implemented yet, document the gap
    skip "Account deactivation not yet implemented"
  end

  # ============================================================================
  # MASS ASSIGNMENT PROTECTION TESTS - High Priority
  # ============================================================================

  test "cannot mass assign account_id on council" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Mass Assign Test", slug: "mass-assign-test")
    end

    post councils_url, params: {
      council: {
        name: "Test",
        account_id: other_account.id,
        space_id: @space.id
      }
    }

    council = Council.last
    assert_equal @account.id, council.account_id
  end

  test "cannot mass assign user_id on conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    other_user = @account.users.create!(email: "other-user@example.com", password: "password123")

    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    post council_conversations_url(council), params: {
      conversation: {
        title: "Test",
        user_id: other_user.id
      }
    }

    conversation = Conversation.last
    assert_equal @user.id, conversation.user_id
  end
end
