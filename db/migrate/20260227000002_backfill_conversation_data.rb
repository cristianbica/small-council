class BackfillConversationData < ActiveRecord::Migration[8.1]
  def up
    # Set all existing conversations to 'council_meeting' type
    execute <<-SQL.squish
      UPDATE conversations
      SET conversation_type = 'council_meeting',
          roe_type = CASE rules_of_engagement
            WHEN 'round_robin' THEN 'open'
            WHEN 'on_demand' THEN 'open'
            WHEN 'moderated' THEN 'open'
            WHEN 'silent' THEN 'open'
            WHEN 'consensus' THEN 'consensus'
            ELSE 'open'
          END
      WHERE conversation_type IS NULL OR conversation_type = 'council_meeting'
    SQL

    # Backfill is_scribe for advisors that match scribe name pattern
    execute <<-SQL.squish
      UPDATE advisors
      SET is_scribe = true
      WHERE LOWER(name) LIKE '%scribe%' OR LOWER(name) LIKE '%scrib%'
    SQL

    # Populate conversation_participants for existing conversations
    # First, create entries for council advisors
    execute <<-SQL.squish
      INSERT INTO conversation_participants (conversation_id, advisor_id, account_id, role, position, created_at, updated_at)
      SELECT DISTINCT
        conv.id as conversation_id,
        ca.advisor_id as advisor_id,
        conv.account_id as account_id,
        CASE
          WHEN a.is_scribe = true THEN 'scribe'
          ELSE 'advisor'
        END as role,
        COALESCE(ca.position, 0) as position,
        NOW() as created_at,
        NOW() as updated_at
      FROM conversations conv
      INNER JOIN councils c ON conv.council_id = c.id
      INNER JOIN council_advisors ca ON c.id = ca.council_id
      INNER JOIN advisors a ON ca.advisor_id = a.id
      WHERE conv.conversation_type = 'council_meeting'
      ON CONFLICT (conversation_id, advisor_id) DO NOTHING
    SQL
  end

  def down
    # Remove all conversation_participants
    execute "DELETE FROM conversation_participants"

    # Reset is_scribe
    execute "UPDATE advisors SET is_scribe = false"

    # Reset conversation types
    execute <<-SQL.squish
      UPDATE conversations
      SET conversation_type = 'council_meeting',
          roe_type = 'open'
    SQL
  end
end
