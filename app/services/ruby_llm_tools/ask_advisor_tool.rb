module RubyLLMTools
  class AskAdvisorTool < RubyLLM::Tool
    description "Ask a question to a specific advisor in the council. This is the ONLY way to communicate with advisors. Creates a message that mentions the advisor, triggering them to generate their own response. YOU CANNOT and SHOULD NOT simulate advisor responses yourself - always use this tool to let them respond authentically."

    param :advisor_name,
      desc: "The name of the advisor to ask (e.g., 'Systems Architect', 'Strategic Advisor'). Must match an advisor in the current space.",
      type: :string

    param :question,
      desc: "The question or message to send to the advisor. Be clear and specific about what you're asking for.",
      type: :string

    param :conversation_id,
      desc: "Optional: The ID of an existing conversation to post in. If not provided, a new conversation will be created.",
      type: :integer

    def execute(advisor_name: nil, question: nil, conversation_id: nil)
      context = Thread.current[:scribe_context]
      return { error: "No context available" } unless context

      if advisor_name.blank?
        return { error: "Advisor name is required" }
      end

      if question.blank?
        return { error: "Question is required" }
      end

      # Find the advisor by name (case-insensitive, handle spaces/underscores/hyphens)
      advisor = find_advisor(context[:space], advisor_name)

      unless advisor
        available_advisors = context[:space].advisors.active.pluck(:name)
        return {
          error: "Advisor '#{advisor_name}' not found",
          available_advisors: available_advisors,
          hint: "Use the exact advisor name from the council"
        }
      end

      begin
        # Find or create conversation
        conversation = if conversation_id.present?
          context[:space].conversations.find_by(id: conversation_id)
        else
          # Create a new conversation for this question
          council = context[:space].councils.first || create_default_council(context[:space], context[:user])

          context[:space].conversations.create!(
            account: context[:space].account,
            council: council,
            user: context[:user],
            title: "Scribe asking #{advisor.name}: #{question.truncate(50)}",
            status: :active,
            rules_of_engagement: :on_demand
          )
        end

        unless conversation
          return { error: "Conversation not found" }
        end

        # Create the message mentioning the advisor
        mention_handle = "@#{parameterize(advisor.name)}"
        full_message = "#{mention_handle} #{question}"

        user_message = conversation.messages.create!(
          account: context[:space].account,
          sender: context[:user],
          role: "user",
          content: full_message,
          status: :complete
        )

        # Create pending placeholder message for the advisor to respond to
        pending_message = conversation.messages.create!(
          account: context[:space].account,
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
          message: "Asked #{advisor.name} in conversation ##{conversation.id}",
          data: {
            advisor_id: advisor.id,
            advisor_name: advisor.name,
            conversation_id: conversation.id,
            conversation_title: conversation.title,
            question: question,
            user_message_id: user_message.id,
            pending_message_id: pending_message.id
          },
          note: "The advisor will respond shortly in conversation ##{conversation.id}. You'll see '[#{advisor.name}] is thinking...' which will be replaced with their actual response."
        }
      rescue => e
        Rails.logger.error "[AskAdvisorTool] Error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        {
          error: "Failed to ask advisor: #{e.message}"
        }
      end
    end

    private

    def find_advisor(space, name)
      # Normalize the search name
      normalized = name.downcase.gsub(/[\s_-]+/, "[-_ ]?")

      space.advisors.active.find do |advisor|
        advisor.name.downcase == name.downcase ||
        advisor.name.downcase.gsub(/[\s_-]+/, "") == name.downcase.gsub(/[\s_-]+/, "") ||
        advisor.name =~ /#{normalized}/i
      end
    end

    def create_default_council(space, user)
      space.councils.create!(
        account: space.account,
        user: user,
        name: "General Council",
        description: "Default council for Scribe conversations"
      )
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
