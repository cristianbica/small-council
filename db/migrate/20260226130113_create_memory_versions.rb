class CreateMemoryVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :memory_versions do |t|
      t.references :memory, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :memory_type, null: false
      t.jsonb :metadata, default: {}
      t.references :created_by, polymorphic: true
      t.text :change_reason

      t.timestamps
    end

    add_index :memory_versions, [ :memory_id, :version_number ], unique: true
    add_index :memory_versions, [ :memory_id, :created_at ]
  end
end
