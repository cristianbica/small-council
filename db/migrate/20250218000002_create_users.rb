class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :account, null: false, foreign_key: true
      t.string :email, null: false
      t.string :password_digest
      t.string :role, default: 'member'
      t.jsonb :preferences, default: {}

      t.timestamps
    end

    add_index :users, [ :account_id, :email ], unique: true
  end
end
