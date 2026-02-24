class AddQueryableFieldsToLLMModels < ActiveRecord::Migration[8.1]
  def change
    add_column :llm_models, :free, :boolean, default: false, null: false
    add_column :llm_models, :context_window, :integer
    add_column :llm_models, :capabilities, :jsonb, default: {}, null: false

    add_index :llm_models, :free
    add_index :llm_models, :context_window
    add_index :llm_models, :capabilities, using: :gin
  end
end
