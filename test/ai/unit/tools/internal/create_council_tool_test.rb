# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class CreateCouncilToolTest < ActiveSupport::TestCase
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
          @tool = CreateCouncilTool.new
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

        test "name returns create_council" do
          assert_equal "create_council", @tool.name
        end

        test "execute creates council with advisors" do
          result = @tool.execute(
            { name: "New Council", advisor_ids: [ @advisor.id ] },
            { space: @space, user: @user }
          )

          assert result[:success]
          council = Council.find(result[:council_id])
          assert_equal "New Council", council.name
          assert_equal @space, council.space
          assert council.advisors.include?(@advisor)
          assert council.advisors.include?(@scribe)
        end

        test "execute denies missing advisors" do
          result = @tool.execute(
            { name: "Council", advisor_ids: [ 9999 ] },
            { space: @space, user: @user }
          )

          assert_not result[:success]
          assert_match(/advisor_ids not found/, result[:error])
        end
      end
    end
  end
end
