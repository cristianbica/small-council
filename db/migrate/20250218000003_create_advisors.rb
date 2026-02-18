class CreateAdvisors < ActiveRecord::Migration[8.1]
  def change
    create_table :advisors do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :system_prompt, null: false
      t.string :model_provider, null: false
      t.string :model_id, null: false
      t.jsonb :model_config, default: {}
      t.jsonb :metadata, default: {}
      t.boolean :global, default: false

      t.timestamps
    end

    add_index :advisors, :model_config, using: :gin
    add_index :advisors, :metadata, using: :gin
  end
end
