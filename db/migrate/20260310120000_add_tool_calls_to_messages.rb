class AddToolCallsToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :tool_calls, :jsonb, default: [], null: false
  end
end
