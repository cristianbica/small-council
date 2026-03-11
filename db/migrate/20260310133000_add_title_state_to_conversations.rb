class AddTitleStateToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :title_state, :string, null: false, default: "user_generated"
    add_index :conversations, :title_state
  end
end
