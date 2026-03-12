# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class ClientChatTest < ActiveSupport::TestCase
    class FakeRubyChat
      attr_reader :added_messages, :tools, :schema

      def initialize
        @added_messages = []
        @tools = []
        @handlers = {}
      end

      def with_tools(tool)
        @tools << tool
      end

      def add_message(message)
        @added_messages << message
      end

      def with_schema(schema)
        @schema = schema
      end

      def on_new_message(&block)
        @handlers[:on_new_message] = block
      end

      def on_end_message(&block)
        @handlers[:on_end_message] = block
      end

      def on_tool_call(&block)
        @handlers[:on_tool_call] = block
      end

      def on_tool_result(&block)
        @handlers[:on_tool_result] = block
      end

      def complete
        OpenStruct.new(content: "done", input_tokens: 1, output_tokens: 2)
      end
    end

    class FakeProvider
      attr_reader :chat_instance

      def initialize
        @chat_instance = FakeRubyChat.new
      end

      def chat(model:)
        @model = model
        @chat_instance
      end
    end

    class FakeTracker
      attr_reader :registered_on

      def register(chat)
        @registered_on = chat
      end
    end

    test "complete sends tools, messages, schema, and trackers" do
      provider = FakeProvider.new
      model = OpenStruct.new(identifier: "model-1")
      chat = AI::Client::Chat.new(provider:, model:)
      tracker = FakeTracker.new

      chat.tools([ :t1, :t2 ])
      chat.instructions("sys")
      chat.add_message(role: :user, content: "hello")
      chat.schema(:schema)
      chat.register_tracker(tracker)

      result = AI::Result.new
      chat.complete(result)

      assert_equal "done", result.response.content
      assert_equal [ :t1, :t2 ], provider.chat_instance.tools
      assert_equal :schema, provider.chat_instance.schema
      assert_equal 2, provider.chat_instance.added_messages.size
      assert_equal :system, provider.chat_instance.added_messages.first[:role]
      assert_equal :user, provider.chat_instance.added_messages.last[:role]
      assert_same chat, tracker.registered_on
    end
  end
end
