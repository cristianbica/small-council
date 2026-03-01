class Space < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  has_many :councils, dependent: :destroy
  has_many :conversations, through: :councils
  has_many :advisors, dependent: :destroy
  has_many :memories, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :account, presence: true

  after_create :create_scribe_advisor

  # Find or create the Scribe advisor for this space
  def scribe_advisor
    # Look for existing Scribe in this space using the is_scribe flag
    scribe = advisors.find_by(is_scribe: true)
    return scribe if scribe.present?

    # Create a new Scribe advisor
    create_scribe_advisor
  end

  # Get all non-Scribe advisors in this space
  def non_scribe_advisors
    advisors.where(is_scribe: false)
  end

  private

  def create_scribe_advisor
    llm_model = account.default_llm_model || account.llm_models.enabled.first

    raise "No LLM model available. Please configure a default model or enable at least one model." unless llm_model

    advisors.create!(
      name: "Scribe",
      system_prompt: <<~PROMPT,
        You are the Scribe, an expert moderator and conversation analyst for this space.

        Your role is to:
        1. Monitor conversations and ensure balanced participation
        2. When all advisors have responded to a message, summarize the discussion or suggest next steps
        3. You can initiate follow-up questions to advisors (maximum 3 consecutive interactions)
        4. When users mention @all or @everyone, coordinate responses from all relevant advisors
        5. Help maintain conversation focus and depth limits based on Rules of Engagement
        6. Users can invite new advisors with /invite @advisor_name

        For Open RoE:
        - Advisors respond only when mentioned by name or with @all
        - Maximum discussion depth is 1 (single round of responses)

        For Consensus RoE:
        - All advisors participate in reaching agreement
        - Maximum discussion depth is 2 (advisors can reply to each other)

        For Brainstorming RoE:
        - All advisors contribute ideas
        - Maximum discussion depth is 2 (iterative idea refinement)

        When responding as scribe:
        - Acknowledge the relevant context from the conversation
        - Provide thoughtful summaries or suggest clarifying questions
        - If the discussion is complete, ask the user if they'd like to conclude
        - Keep responses concise but substantive (2-4 paragraphs)

        Remember: You are the facilitator, ensuring productive conversations while respecting depth limits.
      PROMPT
      llm_model: llm_model,
      global: false,
      is_scribe: true
    )
  rescue => e
    Rails.logger.error "[Space] Failed to create Scribe advisor: #{e.message}"
    # Don't prevent space creation if Scribe creation fails
    nil
  end
end
