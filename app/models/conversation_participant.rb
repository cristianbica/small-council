class ConversationParticipant < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account, optional: true
  belongs_to :conversation
  belongs_to :advisor
  belongs_to :llm_model, optional: true

  # TODO: drop this pointless thing
  enum :role, {
    advisor: "advisor",
    scribe: "scribe"
  }, default: "advisor"

  validates :conversation, presence: true
  validates :advisor, presence: true
  validates :role, presence: true
  validates :advisor_id, uniqueness: { scope: :conversation_id, message: "is already a participant in this conversation" }
  validate :llm_model_belongs_to_account, if: -> { llm_model_id.present? }

  scope :ordered, -> { order(:position, :created_at) }

  after_initialize :normalize_tools
  before_validation :normalize_tools

  before_validation :set_account_from_conversation, on: :create

  def effective_llm_model
    llm_model || advisor&.effective_llm_model || account&.default_llm_model || account&.llm_models&.enabled&.first
  end

  DEFAULT_TOOLS = {
    scribe: %w[memories/* internet/browse_web],
    advisor: []
  }.freeze


  private

  def normalize_tools(tools_list = nil)
    tools_list ||= tools
    list_tools = (tools_list || []).map { |entry| [ entry["ref"], entry["policy"] ] }.to_h
    default_tools = AI.expand_tools(DEFAULT_TOOLS[advisor&.role || :advisor])
    self.tools = AI::Tools::AbstractTool::REGISTRY.keys.map do |ref|
      { "ref" => ref, "policy" => list_tools[ref] || (default_tools.include?(ref) ? "allow" : "deny") }
    end
  end

  def set_account_from_conversation
    self.account_id ||= conversation.account_id if conversation
  end

  def llm_model_belongs_to_account
    return if llm_model_id.blank? || account.blank?

    errors.add(:llm_model, "must belong to this account") unless account.llm_models.exists?(id: llm_model_id)
  end
end
