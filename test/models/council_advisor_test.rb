require "test_helper"

class CouncilAdvisorTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-council-advisors")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

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

    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
  end

  # Validation tests
  test "valid with council and advisor" do
    council_advisor = CouncilAdvisor.new(council: @council, advisor: @advisor, position: 0)
    assert council_advisor.valid?
  end

  test "invalid without council" do
    council_advisor = CouncilAdvisor.new(advisor: @advisor, position: 0)
    assert_not council_advisor.valid?
    assert_includes council_advisor.errors[:council], "can't be blank"
  end

  test "invalid without advisor" do
    council_advisor = CouncilAdvisor.new(council: @council, position: 0)
    assert_not council_advisor.valid?
    assert_includes council_advisor.errors[:advisor], "can't be blank"
  end

  test "invalid with duplicate advisor in same council" do
    CouncilAdvisor.create!(council: @council, advisor: @advisor, position: 0)
    duplicate = CouncilAdvisor.new(council: @council, advisor: @advisor, position: 1)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:advisor_id], "has already been taken"
  end

  test "valid with same advisor in different councils" do
    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(name: "Other Council", user: @user, space: other_space)
    CouncilAdvisor.create!(council: @council, advisor: @advisor, position: 0)
    council_advisor2 = CouncilAdvisor.new(council: other_council, advisor: @advisor, position: 1)
    assert council_advisor2.valid?
  end

  test "valid with different advisors in same council" do
    CouncilAdvisor.create!(council: @council, advisor: @advisor, position: 0)
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "You are another advisor",
      llm_model: @llm_model
    )
    council_advisor = CouncilAdvisor.new(council: @council, advisor: other_advisor, position: 1)
    assert council_advisor.valid?
  end

  test "position defaults to 0" do
    council_advisor = CouncilAdvisor.create!(council: @council, advisor: @advisor)
    assert_equal 0, council_advisor.position
  end

  test "position must be an integer" do
    council_advisor = CouncilAdvisor.new(council: @council, advisor: @advisor, position: 1.5)
    assert_not council_advisor.valid?
    assert_includes council_advisor.errors[:position], "must be an integer"
  end

  test "position must be greater than or equal to 0" do
    council_advisor = CouncilAdvisor.new(council: @council, advisor: @advisor, position: -1)
    assert_not council_advisor.valid?
    assert_includes council_advisor.errors[:position], "must be greater than or equal to 0"
  end

  test "valid with position 0" do
    council_advisor = CouncilAdvisor.new(council: @council, advisor: @advisor, position: 0)
    assert council_advisor.valid?
  end

  test "valid with positive position" do
    council_advisor = CouncilAdvisor.new(council: @council, advisor: @advisor, position: 5)
    assert council_advisor.valid?
  end

  # Association tests
  test "belongs to council" do
    council_advisor = CouncilAdvisor.new
    assert_respond_to council_advisor, :council
  end

  test "belongs to advisor" do
    council_advisor = CouncilAdvisor.new
    assert_respond_to council_advisor, :advisor
  end

  test "council association returns correct council" do
    council_advisor = CouncilAdvisor.create!(council: @council, advisor: @advisor, position: 0)
    assert_equal @council, council_advisor.council
  end

  test "advisor association returns correct advisor" do
    council_advisor = CouncilAdvisor.create!(council: @council, advisor: @advisor, position: 0)
    assert_equal @advisor, council_advisor.advisor
  end
end
