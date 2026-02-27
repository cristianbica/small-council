module RubyLLMTools
  class AdvisorAskAdvisorTool < RubyLLM::Tool
    description "Ask a question to a specific advisor in the council. This is the ONLY way to communicate with other advisors. Creates a message that mentions the advisor, triggering them to generate their own response. YOU CANNOT and SHOULD NOT simulate advisor responses yourself - always use this tool to let them respond authentically. The advisor will respond in the current conversation."

    param :advisor_name,
      desc: "The name of the advisor to ask (e.g., 'Systems Architect', 'Strategic Advisor'). Must match an advisor in the current space.",
      type: :string,
      required: true

    param :question,
      desc: "The question or message to send to the advisor. Be clear and specific about what you're asking for.",
      type: :string,
      required: true

    def execute(advisor_name:, question:)
      context = Thread.current[:advisor_tool_context]
      return { error: "No context available" } unless context

      tool = AdvisorTools::AskAdvisorTool.new
      params = {
        "advisor_name" => advisor_name,
        "question" => question
      }

      result = tool.execute(params, context)

      if result[:success]
        { success: true, message: result[:message], data: result[:data] }
      else
        { error: result[:message], data: result[:data] }
      end
    rescue => e
      Rails.logger.error "[AdvisorAskAdvisorTool] Error: #{e.message}"
      { error: "Failed to ask advisor: #{e.message}" }
    end
  end
end
