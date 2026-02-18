class CreateCouncils < ActiveRecord::Migration[8.1]
  def change
    create_table :councils do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :visibility, default: 'private'
      t.jsonb :configuration, default: {}

      t.timestamps
    end

    add_index :councils, [ :account_id, :name ]
    add_index :councils, :configuration, using: :gin
  end
end
