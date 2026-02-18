class CreateSpaces < ActiveRecord::Migration[8.1]
  def change
    create_table :spaces do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :memory

      t.timestamps
    end

    add_index :spaces, [ :account_id, :name ], unique: true
  end
end
