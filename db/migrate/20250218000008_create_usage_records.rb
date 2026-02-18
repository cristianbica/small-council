class CreateUsageRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_records do |t|
      t.references :account, null: false, foreign_key: true
      t.references :message, null: true, foreign_key: true
      t.string :provider, null: false
      t.string :model, null: false
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.integer :cost_cents, default: 0
      t.datetime :recorded_at

      t.timestamps
    end

    add_index :usage_records, [ :account_id, :recorded_at ]
  end
end
