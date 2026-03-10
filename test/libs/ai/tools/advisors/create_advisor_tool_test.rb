# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Advisors
      class CreateAdvisorToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @context = { space: @space, user: @user, account: @account }
        end

        test "requires_approval is true" do
          assert_equal true, CreateAdvisorTool.requires_approval
        end

        test "read_only is false" do
          assert_equal false, CreateAdvisorTool.read_only
        end

        test "execute creates an advisor" do
          tool = CreateAdvisorTool.new(@context)

          result = tool.execute(
            name: "TestAdvisor",
            system_prompt: "You are a test advisor",
            short_description: "A test advisor"
          )

          assert result[:success]
          assert result[:advisor_id]
          # Advisor names are normalized to lowercase
          assert_equal "testadvisor", result[:name]

          advisor = Advisor.find(result[:advisor_id])
          assert_equal "testadvisor", advisor.name
          assert_equal "You are a test advisor", advisor.system_prompt
          assert_equal "A test advisor", advisor.short_description
          assert_equal @space, advisor.space
          assert_equal false, advisor.is_scribe
        end

        test "execute without short_description" do
          tool = CreateAdvisorTool.new(@context)

          result = tool.execute(
            name: "TestAdvisor",
            system_prompt: "You are a test advisor"
          )

          assert result[:success]
        end

        test "execute returns error for blank name" do
          tool = CreateAdvisorTool.new(@context)

          result = tool.execute(name: "", system_prompt: "Prompt")

          assert_equal false, result[:success]
          assert_equal "name is required", result[:error]
        end

        test "execute returns error for blank system_prompt" do
          tool = CreateAdvisorTool.new(@context)

          result = tool.execute(name: "Test", system_prompt: "")

          assert_equal false, result[:success]
          assert_equal "system_prompt is required", result[:error]
        end

        test "execute returns error for invalid record" do
          tool = CreateAdvisorTool.new(@context)

          Advisor.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(Advisor.new))

          result = tool.execute(name: "Test", system_prompt: "Prompt")

          assert_equal false, result[:success]
          assert result[:error].include?("Failed to create advisor")
        end
      end
    end
  end
end
