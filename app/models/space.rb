class Space < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  has_many :councils, dependent: :destroy
  has_many :conversations, through: :councils

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :account, presence: true

  # Append a conversation memory entry to the space's cumulative memory
  def append_memory(conversation_memory)
    current = self.memory || ""
    new_entry = format_memory_entry(conversation_memory)

    update!(memory: current + "\n\n" + new_entry)
  end

  # Search the space memory for a query string
  def search_memory(query)
    return [] if memory.blank? || query.blank?

    memory.lines.select { |line| line.downcase.include?(query.downcase) }
  end

  private

  def format_memory_entry(memory)
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
    <<~MEMORY
      ## Conversation Summary - #{timestamp}

      **Key Decisions:**
      #{memory["key_decisions"]}

      **Action Items:**
      #{memory["action_items"]}

      **Insights:**
      #{memory["insights"]}

      **Open Questions:**
      #{memory["open_questions"]}
    MEMORY
  end
end
