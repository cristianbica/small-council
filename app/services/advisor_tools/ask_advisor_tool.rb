module AdvisorTools
  class AskAdvisorTool < AdvisorTool
    def tool_name
      "ask_advisor"
    end

    def tool_description
      "Ask a question to a specific advisor in the council. This is the ONLY way to communicate with other advisors. Creates a message that mentions the advisor, triggering them to generate their own response. YOU CANNOT and SHOULD NOT simulate advisor responses yourself - always use this tool to let them respond authentically. The advisor will respond in the current conversation."
    end

    def tool_parameters
      {
        advisor_name: {
          type: "string",
          required: true,
          description: "The name of the advisor to ask (e.g., 'Systems Architect', 'Strategic Advisor'). Must match an advisor in the current space."
        },
        question: {
          type: "string",
          required: true,
          description: "The question or message to send to the advisor. Be clear and specific about what you're asking for."
        }
      }
    end

    def execute(params, context)
      unless context.space
        return {
          success: false,
          message: "No space context available."
        }
      end

      advisor_name = params["advisor_name"].to_s.strip
      question = params["question"].to_s.strip

      if advisor_name.blank?
        return {
          success: false,
          message: "Advisor name is required."
        }
      end

      if question.blank?
        return {
          success: false,
          message: "Question is required."
        }
      end

      # Find the advisor by name (case-insensitive, handle spaces/underscores/hyphens)
      advisor = find_advisor(context.space, advisor_name)

      unless advisor
        available_advisors = context.space.advisors.where.not(id: context.advisor&.id).pluck(:name)
        return {
          success: false,
          message: "Advisor '#{advisor_name}' not found",
          data: {
            available_advisors: available_advisors,
            hint: "Use the exact advisor name from the council"
          }
        }
      end

      # Prevent asking yourself
      if advisor.id == context.advisor&.id
        return {
          success: false,
          message: "You cannot ask yourself. Choose a different advisor."
        }
      end

      begin
        # Use the current conversation from context
        conversation = context.conversation

        unless conversation
          return {
            success: false,
            message: "No conversation context available."
          }
        end

        # Create the message mentioning the advisor
        mention_handle = "@#{parameterize(advisor.name)}"
        full_message = "#{mention_handle} #{question}"

        user_message = conversation.messages.create!(
          account: context.space.account,
          sender: context.advisor || context.user,
          role: "user",
          content: full_message,
          status: :complete
        )

        # Create pending placeholder message for the advisor to respond to
        pending_message = conversation.messages.create!(
          account: context.space.account,
          sender: advisor,
          role: "system",
          content: "[#{advisor.name}] is thinking...",
          status: :pending
        )

        # Enqueue job to generate the advisor's response
        GenerateAdvisorResponseJob.perform_later(
          advisor_id: advisor.id,
          conversation_id: conversation.id,
          message_id: pending_message.id
        )

        {
          success: true,
          message: "Asked #{advisor.name}. They will respond shortly in this conversation.",
          data: {
            advisor_id: advisor.id,
            advisor_name: advisor.name,
            question: question,
            user_message_id: user_message.id,
            pending_message_id: pending_message.id
          }
        }
      rescue => e
        Rails.logger.error "[AdvisorTools::AskAdvisorTool] Error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        {
          success: false,
          message: "Failed to ask advisor: #{e.message}"
        }
      end
    end

    # This tool creates data (messages), so it's not read-only
    def read_only?
      false
    end

    private

    def find_advisor(space, name)
      # Normalize the search name
      normalized = name.downcase.gsub(/[\s_-]+/, "[-_ ]?")

      space.advisors.find do |advisor|
        advisor.name.downcase == name.downcase ||
        advisor.name.downcase.gsub(/[\s_-]+/, "") == name.downcase.gsub(/[\s_-]+/, "") ||
        advisor.name =~ /#{normalized}/i
      end
    end

    def parameterize(string)
      string
        .downcase
        .gsub(/[^a-z0-9\s-]/, "")
        .gsub(/\s+/, "-")
        .gsub(/-+/, "-")
        .gsub(/^-|-$/, "")
    end
  end
end
