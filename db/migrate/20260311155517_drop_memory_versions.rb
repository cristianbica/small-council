class DropMemoryVersions < ActiveRecord::Migration[8.1]
  def up
    drop_table :memory_versions
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
