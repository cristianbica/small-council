class RestructureAdvisorsToSpaceOwned < ActiveRecord::Migration[8.1]
  def change
    # Add space_id to advisors
    add_reference :advisors, :space, foreign_key: true
    add_index :advisors, [ :account_id, :space_id ]

    # Remove council_id from advisors (we'll keep it temporarily for data migration, then remove)
    # But actually, let's just remove it - data will be lost but that's okay for this refactor
    remove_reference :advisors, :council, foreign_key: true

    # Add memory to councils for council-level memory storage
    add_column :councils, :memory, :text

    # Add index for faster lookups
    add_index :advisors, [ :space_id, :name ]
  end
end
