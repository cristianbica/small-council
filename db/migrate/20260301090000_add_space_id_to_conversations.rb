class AddSpaceIdToConversations < ActiveRecord::Migration[8.1]
  def up
    add_reference :conversations, :space, null: true, foreign_key: true, index: false

    execute <<-SQL.squish
      UPDATE conversations
      SET space_id = councils.space_id
      FROM councils
      WHERE conversations.council_id = councils.id
        AND conversations.space_id IS NULL
    SQL

    execute <<-SQL.squish
      UPDATE conversations
      SET space_id = spaces_by_account.space_id
      FROM (
        SELECT DISTINCT ON (account_id) account_id, id AS space_id
        FROM spaces
        ORDER BY account_id, created_at ASC
      ) AS spaces_by_account
      WHERE conversations.space_id IS NULL
        AND conversations.account_id = spaces_by_account.account_id
    SQL

    change_column_null :conversations, :space_id, false
    add_index :conversations, :space_id
  end

  def down
    remove_index :conversations, :space_id
    remove_reference :conversations, :space, foreign_key: true
  end
end
