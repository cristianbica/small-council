# frozen_string_literal: true

require "test_helper"

module AI
  class AssignUnassignAdvisorFlowTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)
      @space = spaces(:one)
      @user = users(:one)
      create_llm_model
      @scribe = @space.scribe_advisor

      @advisor = @space.advisors.create!(
        account: @account,
        name: "Advisor",
        system_prompt: "Prompt"
      )

      @council = @space.councils.create!(
        account: @account,
        user: @user,
        name: "Council"
      )

      @assign_tool = AI::Tools::Internal::AssignAdvisorToCouncilTool.new
      @unassign_tool = AI::Tools::Internal::UnassignAdvisorFromCouncilTool.new
    end

    def create_llm_model
      provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
      provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4",
        enabled: true
      )
    end

    test "assigns and unassigns advisor" do
      assign_result = @assign_tool.execute(
        { council_id: @council.id, advisor_id: @advisor.id },
        { space: @space, advisor: @scribe }
      )

      assert assign_result[:success]
      assert @council.advisors.reload.include?(@advisor)

      unassign_result = @unassign_tool.execute(
        { council_id: @council.id, advisor_id: @advisor.id },
        { space: @space, advisor: @scribe }
      )

      assert unassign_result[:success]
      assert_not @council.advisors.reload.include?(@advisor)
    end
  end
end
