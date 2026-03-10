# frozen_string_literal: true

module AI
  module Tools
    class AbstractTool < RubyLLM::Tool
      REGISTRY = {
        "memories/create" => "AI::Tools::Memories::CreateMemoryTool",
        "memories/list" => "AI::Tools::Memories::ListMemoriesTool",
        "memories/fetch" => "AI::Tools::Memories::FetchMemoryTool",
        "memories/search" => "AI::Tools::Memories::SearchMemoriesTool",
        "memories/update" => "AI::Tools::Memories::UpdateMemoryTool",
        "advisors/create" => "AI::Tools::Advisors::CreateAdvisorTool",
        "advisors/list" => "AI::Tools::Advisors::ListAdvisorsTool",
        "advisors/fetch" => "AI::Tools::Advisors::FetchAdvisorTool",
        "advisors/update" => "AI::Tools::Advisors::UpdateAdvisorTool",
        "internet/browse_web" => "AI::Tools::Internet::BrowseWebTool"
      }.freeze

      class_attribute :requires_approval, default: false
      class_attribute :read_only, default: false

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def name
        REGISTRY.key(self.class.name).parameterize
      end
    end
  end
end
