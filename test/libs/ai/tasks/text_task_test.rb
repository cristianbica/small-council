# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Tasks
    class TextTaskTest < ActiveSupport::TestCase
      class FakeChat
        attr_reader :schema_value, :instructions_value, :messages

        def initialize
          @messages = []
        end

        def schema(value)
          @schema_value = value
        end

        def instructions(value)
          @instructions_value = value
        end

        def add_message(**kwargs)
          @messages << kwargs
        end
      end

      class FakeAgent
        def system_prompt
          "agent prompt"
        end
      end

      setup do
        account = OpenStruct.new(default_llm_model: nil, llm_models: OpenStruct.new(enabled: OpenStruct.new(free: [])))
        @context = AI::Contexts::SpaceContext.new(account: account)
      end

      test "prompt is memoized from AI.prompt" do
        AI.expects(:prompt).once.with(:advisor_profile, context: @context, task: kind_of(TextTask)).returns("rendered")
        task = TextTask.new(context: @context, prompt: :advisor_profile)

        assert_equal "rendered", task.prompt
        assert_equal "rendered", task.prompt
      end

      test "schema resolves when configured and is nil otherwise" do
        task_with_schema = TextTask.new(context: @context, prompt: :advisor_profile, schema: :advisor_profile)
        task_without_schema = TextTask.new(context: @context, prompt: :advisor_profile, schema: nil)
        AI.stubs(:schema).with(:advisor_profile).returns(:schema_class)

        assert_equal :schema_class, task_with_schema.schema
        assert_nil task_without_schema.schema
      end

      test "prepare sets schema instructions and prompt message" do
        chat = FakeChat.new
        task = TextTask.new(context: @context, prompt: :advisor_profile, schema: :advisor_profile)
        task.stubs(:agent).returns(FakeAgent.new)
        task.stubs(:schema).returns(:schema_class)
        task.stubs(:prompt).returns("task prompt")

        task.prepare(chat)

        assert_equal :schema_class, chat.schema_value
        assert_equal "agent prompt", chat.instructions_value
        assert_equal [ { content: "task prompt" } ], chat.messages
      end
    end
  end
end
