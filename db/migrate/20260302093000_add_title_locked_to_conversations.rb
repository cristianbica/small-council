class AddTitleLockedToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :title_locked, :boolean, default: false, null: false
  end
end
