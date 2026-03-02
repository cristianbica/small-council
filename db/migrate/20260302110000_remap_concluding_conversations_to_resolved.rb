class RemapConcludingConversationsToResolved < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE conversations
      SET status = 'resolved'
      WHERE status = 'concluding'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE conversations
      SET status = 'concluding'
      WHERE status = 'resolved'
    SQL
  end
end
