class AddLlmModelToAdvisors < ActiveRecord::Migration[8.1]
  def up
    # Add new reference column
    add_reference :advisors, :llm_model, foreign_key: true, null: true

    # Remove old columns (after data migration - skipped for now)
    remove_column :advisors, :model_provider, :string
    remove_column :advisors, :model_id, :string
  end

  def down
    add_column :advisors, :model_provider, :string
    add_column :advisors, :model_id, :string
    remove_reference :advisors, :llm_model
  end
end
