class CreateCouncilAdvisors < ActiveRecord::Migration[8.1]
  def change
    create_table :council_advisors do |t|
      t.references :council, null: false, foreign_key: true
      t.references :advisor, null: false, foreign_key: true
      t.integer :position, default: 0
      t.jsonb :custom_prompt_override, default: {}

      t.timestamps
    end

    add_index :council_advisors, [ :council_id, :advisor_id ], unique: true
  end
end
