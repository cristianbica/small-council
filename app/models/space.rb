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
  def find_or_create_scribe_advisor
    # Look for existing Scribe in this space
    scribe = advisors.find_by("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")
    return scribe if scribe.present?

    # Create a new Scribe advisor
    llm_model = account.default_llm_model || account.llm_models.enabled.first

    raise "No LLM model available. Please configure a default model or enable at least one model." unless llm_model

    advisors.create!(
      name: "Scribe",
      system_prompt: <<~PROMPT,
        You are the Scribe, an expert moderator and conversation analyst for this space.

        Your role is to:
        1. Read each message carefully and determine which advisor in the council is best suited to respond
        2. When you respond, speak as if you are channeling the expertise of the selected advisor
        3. Consider the expertise, personality, and system prompt of each advisor when making your selection
        4. Ensure balanced participation - don't always select the same advisor
        5. Look for keywords, topics, and context that match each advisor's strengths

        When responding:
        - Acknowledge the relevant context from the conversation
        - Provide thoughtful, expert-level responses that reflect the selected advisor's persona
        - If no single advisor seems perfect, synthesize perspectives from multiple advisors
        - Keep responses concise but substantive (2-4 paragraphs)

        Remember: You are the bridge between the user's needs and the council's collective wisdom.
      PROMPT
      llm_model: llm_model,
      global: false
    )
  end

  # Get all non-Scribe advisors in this space
  def non_scribe_advisors
    advisors.where.not("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")
  end

  private

  def create_scribe_advisor
    find_or_create_scribe_advisor
  rescue => e
    Rails.logger.error "[Space] Failed to create Scribe advisor: #{e.message}"
    # Don't prevent space creation if Scribe creation fails
  end
end
