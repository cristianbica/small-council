class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider_type, null: false
      t.jsonb :credentials, default: {}
      t.boolean :enabled, default: true

      t.timestamps
    end

    add_index :providers, [ :account_id, :name ], unique: true
    add_index :providers, :credentials, using: :gin
  end
end
