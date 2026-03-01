class AddInteractionTypeToModelInteractions < ActiveRecord::Migration[8.1]
  def change
    add_column :model_interactions, :interaction_type, :string, null: false, default: "chat"
    add_index :model_interactions, :interaction_type
  end
end
