require "test_helper"

class SpaceTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:one)
    set_tenant(@account)
  end

  test "should be valid with name and account" do
    space = @account.spaces.new(name: "Test Space")
    assert space.valid?
  end

  test "should require name" do
    space = @account.spaces.new(name: "")
    assert_not space.valid?
    assert_includes space.errors[:name], "can't be blank"
  end

  test "should require unique name per account" do
    @account.spaces.create!(name: "Duplicate")
    space = @account.spaces.new(name: "Duplicate")
    assert_not space.valid?
    assert_includes space.errors[:name], "has already been taken"
  end

  test "should allow same name in different accounts" do
    ActsAsTenant.without_tenant do
      account2 = Account.create!(name: "Other", slug: "other")
      @account.spaces.create!(name: "Shared Name")
      space2 = account2.spaces.new(name: "Shared Name")
      assert space2.valid?
    end
  end

  test "should require account" do
    ActsAsTenant.without_tenant do
      space = Space.new(name: "Test")
      assert_not space.valid?
      assert_includes space.errors[:account], "must exist"
    end
  end

  test "should have many councils" do
    space = @account.spaces.new(name: "Test")
    assert_respond_to space, :councils
  end

  test "should have many conversations through councils" do
    space = @account.spaces.new(name: "Test")
    assert_respond_to space, :conversations
  end

  test "should destroy dependent councils" do
    space = @account.spaces.create!(name: "Test Space")
    user = @account.users.first
    space.councils.create!(name: "Test Council", user: user, account: @account)

    assert_difference("Council.count", -1) do
      space.destroy
    end
  end

  test "acts_as_tenant scopes to account" do
    ActsAsTenant.without_tenant do
      account2 = Account.create!(name: "Other", slug: "other-tenant-test")
      account2.spaces.create!(name: "Other Space")

      @account.spaces.create!(name: "This Space")
    end

    set_tenant(@account)
    # Should only see spaces for this account (account:one has 1 from fixtures + 1 created above)
    assert Space.count >= 1
    assert Space.where(name: "This Space").exists?
    assert_not Space.where(name: "Other Space").exists?
  end

  # scribe_advisor tests
  test "scribe_advisor returns existing scribe without creating a new one" do
    # Ensure an LLM model exists so scribe creation can succeed
    provider = @account.providers.create!(name: "Scribe Test Provider", provider_type: "openai", api_key: "key")
    model = provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4-scribe-test", enabled: true)

    space = @account.spaces.create!(name: "Scribe Existing Test Space")
    # after_create callback should have created a scribe
    scribe = space.advisors.find_by(is_scribe: true)
    advisor_count = space.advisors.count

    # Calling scribe_advisor again should return existing, not create a new one
    result = space.scribe_advisor
    assert_equal advisor_count, space.advisors.reload.count
    assert_not_nil result
    assert result.is_scribe
  end

  test "scribe_advisor creates scribe when none exists" do
    provider = @account.providers.create!(name: "Scribe Create Provider", provider_type: "openai", api_key: "key")
    model = provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4-scribe-create", enabled: true)

    space = @account.spaces.create!(name: "Scribe Create Test Space")
    space.advisors.where(is_scribe: true).destroy_all

    # Now scribe_advisor should create one
    scribe = space.scribe_advisor
    assert_not_nil scribe
    assert scribe.is_scribe
    assert_equal "Scribe", scribe.name
  end

  test "non_scribe_advisors excludes scribe advisor" do
    space = @account.spaces.first
    # Ensure a scribe exists
    scribe = space.scribe_advisor

    # Create a regular advisor
    provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
    model = provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    regular = @account.advisors.create!(
      name: "Expert", system_prompt: "Expert", llm_model: model, space: space
    )

    result = space.non_scribe_advisors
    assert_includes result, regular
    assert_not_includes result, scribe
  end

  test "create_scribe_advisor uses default llm_model when available" do
    provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
    model = provider.llm_models.create!(
      account: @account, name: "Default Model", identifier: "gpt-4-default", enabled: true
    )
    # Set as default
    @account.update!(default_llm_model: model)

    space = @account.spaces.create!(name: "Space With Default Model")
    scribe = space.advisors.find_by(is_scribe: true)
    assert_not_nil scribe
    assert_equal model, scribe.llm_model
  ensure
    @account.update!(default_llm_model: nil)
  end

  test "create_scribe_advisor falls back to first enabled model" do
    # Use a fresh account so we control all models
    ActsAsTenant.without_tenant do
      fresh_account = Account.create!(name: "Fallback Account", slug: "fallback-acct")
      ActsAsTenant.current_tenant = fresh_account
      provider = fresh_account.providers.create!(name: "Fallback", provider_type: "openai", api_key: "key")
      model = provider.llm_models.create!(
        account: fresh_account, name: "Fallback Model", identifier: "gpt-4-fallback", enabled: true
      )

      space = fresh_account.spaces.create!(name: "Space With Fallback Model")
      scribe = space.advisors.find_by(is_scribe: true)
      assert_not_nil scribe
      assert_equal model, scribe.llm_model
    end
  end

  test "create_scribe_advisor does not raise when no model available" do
    @account.update!(default_llm_model: nil)
    # Disable/remove all models for this account
    @account.llm_models.update_all(enabled: false)

    assert_nothing_raised do
      @account.spaces.create!(name: "Space No Model")
    end
  end
end
