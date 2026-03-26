require "test_helper"
require "ostruct"

class ConversationsHelperTest < ActionView::TestCase
  include ConversationsHelper

  ParticipantStub = Struct.new(:tools, :effective_llm_model)

  test "tools_by_category groups tools by prefix and preserves index" do
    categorized = tools_by_category([
      { "ref" => "memories/create", "policy" => "allow" },
      { "ref" => "internet/browse_web", "policy" => "deny" },
      { "ref" => "memories/list", "policy" => "allow" }
    ])

    assert_equal [ "memories", "internet" ], categorized.keys
    assert_equal 2, categorized["memories"].size
    assert_equal 1, categorized["internet"].size
    assert_equal({ ref: "memories/create", policy: "allow", index: 0 }, categorized["memories"][0])
    assert_equal({ ref: "internet/browse_web", policy: "deny", index: 1 }, categorized["internet"][0])
    assert_equal({ ref: "memories/list", policy: "allow", index: 2 }, categorized["memories"][1])
  end

  test "conversation_participant_badge_data counts allow policies and builds tooltip" do
    participant = ParticipantStub.new(
      [
        { "ref" => "internet/browse_web", "policy" => "allow" },
        { "ref" => "memories/create", "policy" => "deny" }
      ],
      OpenStruct.new(name: "Model for Badge")
    )

    data = conversation_participant_badge_data(participant)

    assert_equal "Model for Badge", data[:model_name]
    assert_equal 1, data[:tools_count]
    assert_equal "internet/browse_web", data[:tools_tooltip]
  end

  test "conversation_participant_badge_data uses fallback model label and no-tools tooltip" do
    participant = ParticipantStub.new(
      [ { "ref" => "memories/create", "policy" => "deny" } ],
      nil
    )

    data = conversation_participant_badge_data(participant)

    assert_equal "Inherit default", data[:model_name]
    assert_equal "Inherit default", data[:model_label]
    assert_equal 0, data[:tools_count]
    assert_equal "No tools allowed", data[:tools_tooltip]
  end

  test "conversation_participant_badge_data truncates long model labels" do
    long_name = "Very Long Model Name For Participant Badges"
    participant = ParticipantStub.new([], OpenStruct.new(name: long_name))

    data = conversation_participant_badge_data(participant)

    assert_equal long_name, data[:model_name]
    assert data[:model_label].end_with?("...")
  end

  test "conversation_participant_badge_data ignores non-hash tool entries" do
    participant = ParticipantStub.new(
      [
        "internet/browse_web",
        { "ref" => "memories/create", "policy" => "allow" }
      ],
      nil
    )

    data = conversation_participant_badge_data(participant)

    assert_equal 1, data[:tools_count]
    assert_equal "memories/create", data[:tools_tooltip]
  end
end
