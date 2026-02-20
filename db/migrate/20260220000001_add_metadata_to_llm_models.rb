class AddMetadataToLLMModels < ActiveRecord::Migration[8.1]
  def change
    add_column :llm_models, :metadata, :jsonb, default: {}
    add_index :llm_models, :metadata, using: :gin
  end
end
