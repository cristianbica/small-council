class CreateModelInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :model_interactions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true

      t.integer    :sequence,         null: false, default: 0
      t.jsonb      :request_payload,  null: false, default: {}
      t.jsonb      :response_payload, null: false, default: {}
      t.string     :model_identifier
      t.integer    :input_tokens,     default: 0
      t.integer    :output_tokens,    default: 0
      t.float      :duration_ms

      t.timestamps
    end

    add_index :model_interactions, [ :message_id, :sequence ]
    add_index :model_interactions, :request_payload, using: :gin
    add_index :model_interactions, :response_payload, using: :gin
  end
end
