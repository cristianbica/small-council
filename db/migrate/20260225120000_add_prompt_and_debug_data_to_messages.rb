class AddPromptAndDebugDataToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :prompt_text, :text
    add_column :messages, :debug_data, :jsonb, default: {}

    add_index :messages, :debug_data, using: :gin
  end
end
