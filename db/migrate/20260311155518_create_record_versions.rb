class CreateRecordVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :record_versions do |t|
      t.references :versionable, polymorphic: true, null: false
      t.integer :version_number, null: false
      t.bigint :previous_version_id
      t.references :whodunnit, polymorphic: true
      t.jsonb :object_data, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :record_versions, [ :versionable_type, :versionable_id, :version_number ],
              unique: true, name: 'index_record_versions_unique'
    add_index :record_versions, [ :versionable_type, :versionable_id, :created_at ]
    add_index :record_versions, :previous_version_id
  end
end
