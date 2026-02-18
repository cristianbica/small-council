require "test_helper"

class SpacesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
  end

  test "should redirect to sign in when not authenticated" do
    get spaces_url
    assert_redirected_to sign_in_url
  end

  test "should get index when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get spaces_url
    assert_response :success
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get new_space_url
    assert_response :success
  end

  test "should create space" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_difference("Space.count") do
      post spaces_url, params: { space: { name: "Test Space", description: "A test space" } }
    end

    space = Space.last
    assert_redirected_to space_councils_path(space)
    assert_equal "Space created successfully.", flash[:notice]
    assert_equal space.id, session[:space_id]
  end

  test "should show space and switch to it" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")
    get space_url(space)
    assert_redirected_to space_councils_path(space)
    assert_equal space.id, session[:space_id]
  end

  test "should get edit" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")
    get edit_space_url(space)
    assert_response :success
  end

  test "should update space" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")
    patch space_url(space), params: { space: { name: "Updated Name" } }
    assert_redirected_to space_councils_path(space)
    assert_equal "Updated Name", space.reload.name
  end

  test "should not create space with invalid params" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_no_difference("Space.count") do
      post spaces_url, params: { space: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "should not access space from other account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create other account and space without tenant scoping (so space gets correct account_id)
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Account", slug: "other-space-test-#{Time.now.to_i}")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Space")
    end

    # Verify other_account is different from @account
    assert other_account.id != @account.id, "other_account.id (#{other_account.id}) should not equal @account.id (#{@account.id})"

    # Verify the space belongs to other_account
    assert_equal other_account.id, other_space.account_id

    # Verify other_space is not in @account's spaces
    assert_not @account.spaces.exists?(other_space.id)

    # Now test the controller - should return 404 (Rails catches RecordNotFound in production)
    get space_url(other_space)
    assert_response :not_found
  end

  test "update renders edit on validation failure" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Test Space")

    patch space_url(space), params: { space: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "new renders form" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_space_url
    assert_response :success
    assert_select "form[action=?]", spaces_path
  end

  # ============================================================================
  # SECURITY TESTS - Added as part of security audit
  # ============================================================================

  test "cannot access space from different account via ID manipulation" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create space in second account (from fixture)
    second_account = accounts(:two)
    second_space = ActsAsTenant.without_tenant do
      second_account.spaces.create!(name: "Second Account Space")
    end

    # Try to access space from other account
    get space_url(second_space)
    assert_response :not_found
  end

  test "cannot edit space from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    second_account = accounts(:two)
    second_space = ActsAsTenant.without_tenant do
      second_account.spaces.create!(name: "Second Account Space")
    end

    # Space won't be found in Current.account.spaces scope -> 404
    get edit_space_url(second_space)
    assert_response :not_found
  end

  test "cannot update space from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    second_account = accounts(:two)
    second_space = ActsAsTenant.without_tenant do
      second_account.spaces.create!(name: "Second Account Space")
    end

    # Space won't be found in Current.account.spaces scope -> 404
    patch space_url(second_space), params: {
      space: { name: "Hacked Name" }
    }
    assert_response :not_found

    # Verify name wasn't changed
    ActsAsTenant.without_tenant do
      assert_equal "Second Account Space", second_space.reload.name
    end
  end

  test "cannot manipulate account_id via space form" do
    sign_in_as(@user)
    set_tenant(@account)

    second_account = accounts(:two)

    assert_difference("Space.count") do
      post spaces_url, params: {
        space: {
          name: "Test Space",
          description: "Test",
          account_id: second_account.id  # Attempting to set account
        }
      }
    end

    space = Space.last
    assert_equal @account.id, space.account_id
    refute_equal second_account.id, space.account_id
  end

  test "index only shows spaces from current account" do
    # Create spaces in different accounts
    @account.spaces.create!(name: "My Space")

    second_account = accounts(:two)
    ActsAsTenant.without_tenant do
      second_account.spaces.create!(name: "Other Account Space")
    end

    sign_in_as(@user)
    set_tenant(@account)

    get spaces_url
    assert_response :success
    assert_select "h1", "Spaces"
    # Should see our space but not the other account's space (view uses h2 for space names)
    assert_select "h2", text: /My Space/
    assert_select "h2", { text: /Other Account Space/, count: 0 }
  end

  test "space switching via show action works correctly" do
    sign_in_as(@user)
    set_tenant(@account)

    space1 = @account.spaces.create!(name: "Space One")
    space2 = @account.spaces.create!(name: "Space Two")

    # Switch to space1
    get space_url(space1)
    assert_redirected_to space_councils_path(space1)
    assert_equal space1.id, session[:space_id]

    # Switch to space2
    get space_url(space2)
    assert_redirected_to space_councils_path(space2)
    assert_equal space2.id, session[:space_id]
  end

  test "memory action shows space memory and resolved conversations" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Memory Test Space", memory: "Test memory content")
    council = space.councils.create!(name: "Test Council", user: @user, account: @account)
    conversation = council.conversations.create!(
      title: "Resolved Conversation",
      user: @user,
      account: @account,
      status: :resolved,
      context: { "memory" => { "key_decisions" => "Decision 1" }.to_json }
    )

    get memory_space_url(space)
    assert_response :success
    assert_select "h1", /Memory: Memory Test Space/
    assert_select ".prose", /Test memory content/
    assert_select ".card-title", /Resolved Conversation/
  end

  test "search_memory action finds matching content" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Search Test Space", memory: "Line about Python\nLine about Ruby\nLine about Rails")

    get search_memory_space_url(space), params: { q: "Python" }
    assert_response :success
    assert_select "h2", /1 matches found/
  end

  test "search_memory handles no matches" do
    sign_in_as(@user)
    set_tenant(@account)
    space = @account.spaces.create!(name: "Search Test Space", memory: "Some content")

    get search_memory_space_url(space), params: { q: "nonexistent" }
    assert_response :success
    assert_select "p", /No matches found/
  end

  test "cannot access memory from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    second_account = accounts(:two)
    second_space = ActsAsTenant.without_tenant do
      second_account.spaces.create!(name: "Other Account Space")
    end

    get memory_space_url(second_space)
    assert_response :not_found
  end
end
