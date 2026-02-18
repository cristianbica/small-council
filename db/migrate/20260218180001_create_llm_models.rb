class CreateLlmModels < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_models do |t|
      t.references :provider, null: false, foreign_key: true
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :identifier, null: false
      t.boolean :enabled, default: true
      t.boolean :deprecated, default: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :llm_models, [ :provider_id, :identifier ], unique: true
    add_index :llm_models, :deleted_at
    add_index :llm_models, :account_id

    add_foreign_key :llm_models, :accounts
  end
end
