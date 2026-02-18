class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :sender, polymorphic: true, null: false
      t.string :role, null: false
      t.text :content
      t.jsonb :content_blocks, default: []
      t.jsonb :metadata, default: {}
      t.string :status, default: 'complete'

      t.timestamps
    end

    add_index :messages, [ :conversation_id, :created_at ]
    add_index :messages, :metadata, using: :gin
  end
end
