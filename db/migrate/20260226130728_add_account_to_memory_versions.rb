class AddAccountToMemoryVersions < ActiveRecord::Migration[8.1]
  def change
    add_reference :memory_versions, :account, null: false, foreign_key: true
  end
end
