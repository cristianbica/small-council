class CreateScribeChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :scribe_chat_messages do |t|
      t.references :space, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :scribe_chat_messages, [ :space_id, :user_id, :created_at ]
  end
end
