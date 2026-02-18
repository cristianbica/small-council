class AddSpaceIdToCouncils < ActiveRecord::Migration[8.1]
  def change
    add_reference :councils, :space, null: true, foreign_key: true

    # Add index for performance
    add_index :councils, [ :space_id, :created_at ]
  end
end
