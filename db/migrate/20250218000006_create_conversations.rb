class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :council, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.string :status, default: 'active'
      t.jsonb :context, default: {}
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :conversations, [ :account_id, :last_message_at ]
    add_index :conversations, :context, using: :gin
  end
end
