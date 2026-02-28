class AddConversationRefactor < ActiveRecord::Migration[8.1]
  def change
    # Add conversation_type to conversations
    add_column :conversations, :conversation_type, :string, null: false, default: 'council_meeting'
    add_index :conversations, :conversation_type

    # Make council_id nullable for adhoc conversations
    change_column_null :conversations, :council_id, true

    # Add roe_type to replace rules_of_engagement
    add_column :conversations, :roe_type, :string, null: false, default: 'open'
    add_index :conversations, :roe_type

    # Create conversation_participants join table with account_id
    create_table :conversation_participants do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :advisor, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :role, null: false, default: 'advisor'  # 'advisor' | 'scribe'
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :conversation_participants, [ :conversation_id, :advisor_id ], unique: true, name: 'index_conversation_participants_unique'

    # Add message threading and pending state
    add_column :messages, :in_reply_to_id, :bigint
    add_index :messages, :in_reply_to_id
    add_foreign_key :messages, :messages, column: :in_reply_to_id

    add_column :messages, :pending_advisor_ids, :jsonb, default: []
    add_index :messages, :pending_advisor_ids, using: :gin

    # Add scribe flag to advisors (instead of name detection)
    add_column :advisors, :is_scribe, :boolean, default: false
    add_index :advisors, :is_scribe

    # Add scribe_initiated_count for conversation lifecycle
    add_column :conversations, :scribe_initiated_count, :integer, default: 0
  end
end
