class ChangeUserEmailIndexToGlobal < ActiveRecord::Migration[8.1]
  def up
    # Remove old scoped index
    remove_index :users, [ :account_id, :email ]

    # Add new global unique index on email
    add_index :users, :email, unique: true
  end

  def down
    # Revert back to scoped index
    remove_index :users, :email
    add_index :users, [ :account_id, :email ], unique: true
  end
end
