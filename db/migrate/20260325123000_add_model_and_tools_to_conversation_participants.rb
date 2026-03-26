class AddModelAndToolsToConversationParticipants < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversation_participants, :llm_model, foreign_key: true, index: true
    add_column :conversation_participants, :tools, :jsonb, default: []
    add_index :conversation_participants, :tools, using: :gin
  end
end
