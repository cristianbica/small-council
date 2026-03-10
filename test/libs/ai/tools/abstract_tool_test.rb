# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    class AbstractToolTest < ActiveSupport::TestCase
      test "AbstractTool inherits from RubyLLM::Tool" do
        assert AI::Tools::AbstractTool < RubyLLM::Tool
      end

      test "AbstractTool has empty defaults for metadata" do
        assert_equal false, AI::Tools::AbstractTool.requires_approval
        assert_equal false, AI::Tools::AbstractTool.read_only
      end

      test "instance has access to class metadata" do
        tool = AI::Tools::Memories::CreateMemoryTool.new({})
        assert_equal true, tool.requires_approval
        assert_equal false, tool.read_only
      end

      test "instance requires context" do
        assert_raises(ArgumentError) { AI::Tools::AbstractTool.new }
      end

      test "instance stores context" do
        context = { space: :test, user: :test }
        tool = AI::Tools::Memories::CreateMemoryTool.new(context)
        assert_equal context, tool.context
      end

      test "REGISTRY is a frozen hash" do
        assert AI::Tools::AbstractTool::REGISTRY.is_a?(Hash)
        assert AI::Tools::AbstractTool::REGISTRY.frozen?
      end

      test "REGISTRY contains expected tool mappings" do
        registry = AI::Tools::AbstractTool::REGISTRY

        # Memories
        assert_equal "AI::Tools::Memories::CreateMemoryTool", registry["memories/create"]
        assert_equal "AI::Tools::Memories::ListMemoriesTool", registry["memories/list"]
        assert_equal "AI::Tools::Memories::FetchMemoryTool", registry["memories/fetch"]
        assert_equal "AI::Tools::Memories::SearchMemoriesTool", registry["memories/search"]
        assert_equal "AI::Tools::Memories::UpdateMemoryTool", registry["memories/update"]

        # Advisors
        assert_equal "AI::Tools::Advisors::CreateAdvisorTool", registry["advisors/create"]
        assert_equal "AI::Tools::Advisors::ListAdvisorsTool", registry["advisors/list"]
        assert_equal "AI::Tools::Advisors::FetchAdvisorTool", registry["advisors/fetch"]
        assert_equal "AI::Tools::Advisors::UpdateAdvisorTool", registry["advisors/update"]

        # Internet
        assert_equal "AI::Tools::Internet::BrowseWebTool", registry["internet/browse_web"]
      end
    end
  end
end
