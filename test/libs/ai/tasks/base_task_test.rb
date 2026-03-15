# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Tasks
    class BaseTaskTest < ActiveSupport::TestCase
      class ConcreteTask < BaseTask
        self.agent = :advisor

        def prepare(chat)
          chat.instructions("prepared")
        end
      end

      class EmptyTask < BaseTask
        # Doesn't override prepare
      end

      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @user = users(:one)
        @context = AI::Contexts::SpaceContext.new(
          account: @account,
          space: @space
        )
      end

      test "initialize stores context and tools" do
        task = ConcreteTask.new(context: @context, tools: [ "tool1" ])

        assert_equal @context, task.context
      end

      test "agent resolves agent class" do
        task = ConcreteTask.new(context: @context)

        agent = task.agent
        assert_instance_of AI::Agents::AdvisorAgent, agent
      end

      test "prepare raises NotImplementedError in base class" do
        task = BaseTask.new(context: @context)

        assert_raises(NotImplementedError) do
          task.prepare(nil)
        end
      end

      test "run orchestrates full execution flow" do
        task = ConcreteTask.new(context: @context)
        result = AI::Result.new

        chat = mock("chat")
        AI::Client.expects(:chat).returns(chat)
        chat.expects(:tools)
        chat.expects(:instructions).with("prepared")

        # Create a tracker that responds to :register
        tracker = mock("tracker")
        tracker.expects(:respond_to?).with(:register).returns(true)
        chat.expects(:register_tracker).with(tracker)
        chat.expects(:complete).with(result)

        # Mock agent to return tools
        AI::Agents::AdvisorAgent.any_instance.stubs(:tools).returns([ "tool1" ])
        AI::Agents::AdvisorAgent.any_instance.stubs(:system_prompt).returns("agent prompt")

        returned_result = task.run(result, trackers: [ tracker ])

        assert_equal result, returned_result
      end



      test "run works without tools" do
        task = ConcreteTask.new(context: @context)
        result = AI::Result.new

        chat = mock("chat")
        AI::Client.expects(:chat).returns(chat)
        # No tools to register
        chat.expects(:tools).never
        chat.expects(:instructions).with("prepared")
        chat.expects(:complete).with(result)

        # Agent returns no tools
        AI::Agents::AdvisorAgent.any_instance.stubs(:tools).returns([])

        task.run(result)
      end

      test "register_tools does nothing when agent has no tools" do
        task = ConcreteTask.new(context: @context)
        chat = mock("chat")

        # Agent with no tools returns empty array
        AI::Agents::AdvisorAgent.any_instance.stubs(:tools).returns([])
        chat.expects(:tools).never

        task.send(:register_tools, chat)
      end

      test "register_trackers skips trackers without register method" do
        task = ConcreteTask.new(context: @context)
        chat = mock("chat")
        tracker_without_register = Object.new

        chat.expects(:register_tracker).never

        task.send(:register_trackers, chat, [ tracker_without_register ])
      end

      test "register_trackers registers trackers with register method" do
        task = ConcreteTask.new(context: @context)
        chat = mock("chat")
        tracker = mock("tracker")
        tracker.expects(:respond_to?).with(:register).returns(true)
        chat.expects(:register_tracker).with(tracker)

        task.send(:register_trackers, chat, [ tracker ])
      end
    end
  end
end
