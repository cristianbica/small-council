require "test_helper"
require Rails.root.join("db/migrate/20260302123000_normalize_advisor_names_to_canonical_handles")
require Rails.root.join("db/migrate/20260302123100_enforce_canonical_advisor_names")

class AdvisorNameCanonicalMigrationsTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Migration Test Account", slug: "migration-test-account")
    set_tenant(@account)
    @space = @account.spaces.create!(name: "Migration Test Space")

    provider = @account.providers.create!(
      name: "Migration Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )

    @llm_model = provider.llm_models.create!(
      account: @account,
      name: "Migration Test Model",
      identifier: "migration-test-model"
    )
  end

  test "normalize migration fails fast for invalid canonical names" do
    migration = NormalizeAdvisorNamesToCanonicalHandles.new
    migration.stubs(:execute).with("SELECT id, space_id, name FROM advisors ORDER BY id").returns([
      { "id" => 10, "space_id" => 5, "name" => "___" }
    ])

    error = assert_raises(ActiveRecord::MigrationError) { migration.up }

    assert_includes error.message, "Invalid rows"
    assert_includes error.message, "advisor_id: 10"
  end

  test "normalize migration fails fast for canonical collisions" do
    migration = NormalizeAdvisorNamesToCanonicalHandles.new
    migration.stubs(:execute).with("SELECT id, space_id, name FROM advisors ORDER BY id").returns([
      { "id" => 11, "space_id" => 7, "name" => "Data Science" },
      { "id" => 12, "space_id" => 7, "name" => "data-science" }
    ])

    error = assert_raises(ActiveRecord::MigrationError) { migration.up }

    assert_includes error.message, "Collisions"
    assert_includes error.message, "canonical_name: \"data-science\""
    assert_includes error.message, "advisor_id: 11"
    assert_includes error.message, "advisor_id: 12"
  end

  test "enforced canonical constraint rejects invalid advisor names at db level" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Advisor.insert_all!([
        advisor_attrs(name: "data_science")
      ])
    end
  end

  test "enforced unique lower-name index rejects canonical collisions in same space" do
    Advisor.insert_all!([
      advisor_attrs(name: "data")
    ])

    assert_raises(ActiveRecord::RecordNotUnique) do
      Advisor.insert_all!([
        advisor_attrs(name: "data")
      ])
    end
  end

  private

  def advisor_attrs(name:)
    {
      account_id: @account.id,
      llm_model_id: @llm_model.id,
      space_id: @space.id,
      name: name,
      system_prompt: "Test prompt",
      created_at: Time.current,
      updated_at: Time.current
    }
  end
end
