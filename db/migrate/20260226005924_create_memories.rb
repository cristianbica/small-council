class CreateMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :memories do |t|
      # Multi-tenancy
      t.references :account, null: false, foreign_key: true

      # Core relationships
      t.references :space, null: false, foreign_key: true

      # Polymorphic source (optional - links to conversation or other source)
      t.references :source, polymorphic: true, null: true

      # Memory metadata
      t.string :title, null: false
      t.text :content, null: false
      t.string :memory_type, null: false, default: "knowledge"
      t.jsonb :metadata, default: {}
      t.string :status, default: "active"

      # For page-like ordering
      t.integer :position, default: 0

      # Polymorphic creator/updater (User or Advisor)
      t.references :created_by, polymorphic: true, null: true
      t.references :updated_by, polymorphic: true, null: true

      t.timestamps
    end

    # Indexes for efficient querying
    add_index :memories, [ :space_id, :memory_type ]
    add_index :memories, [ :space_id, :status ]
    add_index :memories, [ :space_id, :position ]
    add_index :memories, :metadata, using: :gin
    add_index :memories, [ :account_id, :created_at ]
  end
end
