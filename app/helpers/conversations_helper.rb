module ConversationsHelper
  def conversation_participant_badge_data(participant)
    model_name = participant.effective_llm_model&.name || "Inherit default"
    allowed_tool_refs = participant.tools.filter_map do |entry|
      next unless entry.is_a?(Hash)
      next unless entry["policy"].to_s == "allow"

      entry["ref"].to_s
    end

    {
      model_name: model_name,
      model_label: truncate(model_name, length: 22, omission: "..."),
      tools_count: allowed_tool_refs.count,
      tools_tooltip: allowed_tool_refs.any? ? allowed_tool_refs.join("\n") : "No tools allowed"
    }
  end

  def tools_by_category(tools)
    categorized = Hash.new { |h, k| h[k] = [] }
    index = 0
    tools.each do |tool|
      ref = tool["ref"]
      policy = tool["policy"]
      category, _name = ref.to_s.split("/", 2)
      categorized[category] << { ref: ref, policy: policy, index: index }
      index += 1
    end
    categorized
  end
end
