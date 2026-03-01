require "test_helper"

class CouncilTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-councils")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")

    # Create provider and model for advisors
    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )
  end

  # Validation tests
  test "valid with name, account, user, and space" do
    council = @account.councils.new(name: "Test Council", user: @user, space: @space)
    assert council.valid?
  end

  test "invalid without space" do
    council = @account.councils.new(name: "Test Council", user: @user)
    assert_not council.valid?
    assert_includes council.errors[:space], "must exist"
  end

  test "invalid without name" do
    council = @account.councils.new(user: @user, space: @space)
    assert_not council.valid?
    assert_includes council.errors[:name], "can't be blank"
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      council = Council.new(name: "Orphan Council", user: @user, space: @space)
      assert_not council.valid?
      assert_includes council.errors[:account], "can't be blank"
    end
  end

  test "invalid without user" do
    council = @account.councils.new(name: "No User Council", space: @space)
    assert_not council.valid?
    assert_includes council.errors[:user], "can't be blank"
  end

  # Association tests
  test "belongs to account" do
    council = Council.new
    assert_respond_to council, :account
  end

  test "belongs to user" do
    council = Council.new
    assert_respond_to council, :user
  end

  test "belongs to space" do
    council = Council.new
    assert_respond_to council, :space
  end

  test "has many council_advisors" do
    council = Council.new
    assert_respond_to council, :council_advisors
  end

  test "has many advisors through council_advisors" do
    council = Council.new
    assert_respond_to council, :advisors
  end

  test "has many conversations" do
    council = Council.new
    assert_respond_to council, :conversations
  end

  test "dependent destroy removes associated council_advisors" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: @space
    )
    council.council_advisors.create!(advisor: advisor, position: 0)
    assert_difference("CouncilAdvisor.count", -1) do
      council.destroy
    end
  end

  test "dependent destroy removes associated conversations" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: @space
    )
    council.council_advisors.create!(advisor: advisor, position: 0)
    conversation = council.create_conversation!(user: @user, title: "Test Conversation")
    assert_difference("Conversation.count", -1) do
      council.destroy
    end
  end

  test "advisors through association works" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: @space
    )
    council.council_advisors.create!(advisor: advisor, position: 0)
    assert_includes council.advisors, advisor
  end

  # Enum tests
  test "defaults to private visibility" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    assert_equal "private_visibility", council.visibility
    assert council.visibility_private_visibility?
  end

  test "can be set to shared visibility" do
    council = @account.councils.create!(name: "Shared Council", user: @user, space: @space, visibility: "shared")
    assert_equal "shared", council.visibility
    assert council.visibility_shared?
  end

  test "visibility enum with prefix works correctly" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    assert council.visibility_private_visibility?
    assert_not council.visibility_shared?

    council.visibility_shared!
    assert council.visibility_shared?
    assert_not council.visibility_private_visibility?
  end

  test "invalid visibility raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.councils.create!(name: "Invalid Council", user: @user, space: @space, visibility: "public")
    end
  end

  test "valid visibility values are private and shared" do
    assert_equal({ "private_visibility" => "private", "shared" => "shared" }, Council.visibilities)
  end

  # ensure_scribe_assigned tests
  test "ensure_scribe_assigned does nothing when no scribe exists in space" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    # Stub scribe_advisor to return nil (simulates space with no scribe available)
    council.stubs(:scribe_advisor).returns(nil)
    assert_nothing_raised { council.ensure_scribe_assigned }
  end

  test "ensure_scribe_assigned does not add duplicate scribe" do
    scribe = @account.advisors.create!(
      name: "Scribe", system_prompt: "You are a scribe",
      llm_model: @llm_model, space: @space, is_scribe: true
    )
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    council.council_advisors.create!(advisor: scribe)

    council.ensure_scribe_assigned
    council.ensure_scribe_assigned

    assert_equal 1, council.advisors.where(is_scribe: true).count
  end

  test "ensure_scribe_assigned adds scribe when scribe exists in space but not in council" do
    # Destroy any auto-created scribe, then create one explicitly
    @space.advisors.where(is_scribe: true).destroy_all
    scribe = @account.advisors.create!(
      name: "Scribe", system_prompt: "You are a scribe",
      llm_model: @llm_model, space: @space, is_scribe: true
    )
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    council.ensure_scribe_assigned

    assert_includes council.advisors.reload, scribe
  end

  # create_conversation! tests
  test "create_conversation! creates message when initial_message present" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = council.create_conversation!(
      user: @user, title: "Chat", initial_message: "Hello advisors"
    )
    assert_equal 1, conversation.messages.count
    assert_equal "Hello advisors", conversation.messages.first.content
  end

  test "create_conversation! does not create message when initial_message blank" do
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = council.create_conversation!(user: @user, title: "Silent Chat")
    assert_equal 0, conversation.messages.count
  end

  test "create_conversation! sets participant role to scribe for scribe advisor" do
    scribe = @account.advisors.create!(
      name: "Scribe", system_prompt: "Scribe prompt",
      llm_model: @llm_model, space: @space, is_scribe: true
    )
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    council.council_advisors.create!(advisor: scribe, position: 0)

    conversation = council.create_conversation!(user: @user, title: "Meeting")
    participant = conversation.conversation_participants.find_by(advisor: scribe)
    assert_equal "scribe", participant.role
  end

  test "create_conversation! sets participant role to advisor for non-scribe advisors" do
    regular = @account.advisors.create!(
      name: "Expert", system_prompt: "Expert prompt",
      llm_model: @llm_model, space: @space, is_scribe: false
    )
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    council.council_advisors.create!(advisor: regular, position: 0)

    conversation = council.create_conversation!(user: @user, title: "Meeting")
    participant = conversation.conversation_participants.find_by(advisor: regular)
    assert_equal "advisor", participant.role
  end

  # available_advisors test
  test "available_advisors returns non-scribe advisors from space" do
    @space.advisors.where(is_scribe: true).destroy_all
    scribe = @account.advisors.create!(
      name: "Scribe", system_prompt: "Scribe",
      llm_model: @llm_model, space: @space, is_scribe: true
    )
    regular = @account.advisors.create!(
      name: "Regular", system_prompt: "Regular",
      llm_model: @llm_model, space: @space, is_scribe: false
    )
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    result = council.available_advisors
    assert_includes result, regular
    assert_not_includes result, scribe
  end
end
