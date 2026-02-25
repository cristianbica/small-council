class Council < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :user
  belongs_to :space

  has_many :council_advisors, dependent: :destroy
  has_many :advisors, through: :council_advisors
  has_many :conversations, dependent: :destroy

  enum :visibility, {
    private_visibility: "private",
    shared: "shared"
  }, default: "private", prefix: true

  validates :name, presence: true
  validates :account, presence: true
  validates :user, presence: true
  validates :space, presence: true

  # Find or create a Scribe advisor for this council
  # The Scribe is used in Moderated RoE mode to moderate discussions
  def find_or_create_scribe_advisor
    # First check if council already has a Scribe
    existing_scribe = advisors.find_by("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")
    return existing_scribe if existing_scribe.present?

    # Look for a global Scribe advisor in the account
    global_scribe = account.advisors.global.find_by("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")

    if global_scribe.present?
      # Add existing global Scribe to this council
      council_advisors.create!(advisor: global_scribe)
      return global_scribe
    end

    # Create a new global Scribe advisor
    llm_model = account.default_llm_model || account.llm_models.enabled.first

    raise "No LLM model available. Please configure a default model or enable at least one model." unless llm_model

    scribe = account.advisors.create!(
      name: "Scribe",
      system_prompt: <<~PROMPT,
        You are the Scribe, an expert moderator and conversation analyst.

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
      global: true
    )

    # Add Scribe to this council
    council_advisors.create!(advisor: scribe)

    scribe
  end
end
