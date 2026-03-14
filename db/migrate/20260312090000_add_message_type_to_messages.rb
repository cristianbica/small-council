class AddMessageTypeToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :message_type, :string, default: "chat", null: false
    add_index :messages, :message_type
  end
end
