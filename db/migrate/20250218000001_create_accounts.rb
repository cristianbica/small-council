class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.jsonb :settings, default: {}
      t.datetime :trial_ends_at

      t.timestamps
    end

    add_index :accounts, :slug, unique: true
    add_index :accounts, :settings, using: :gin
  end
end
