# Data migration: Migrate existing space.memory to memories table
# This migration preserves existing space knowledge by creating summary-type memories
class MigrateSpaceMemoryToMemories < ActiveRecord::Migration[8.1]
  def up
    # Migrate each space that has memory content
    Space.where.not(memory: [ nil, "" ]).find_each do |space|
      # Create a summary memory from the space's existing memory
      space.memories.create!(
        account: space.account,
        title: "#{space.name} - Cumulative Knowledge",
        content: space.memory,
        memory_type: "summary",
        status: "active",
        position: 0,
        # Use a system marker to indicate this was migrated
        metadata: {
          migrated_from_space_memory: true,
          migrated_at: Time.current.iso8601,
          original_space_id: space.id
        }
      )

      Rails.logger.info "[MigrateSpaceMemory] Migrated space #{space.id} memory to summary memory"
    end

    puts "Migrated #{Space.where.not(memory: [ nil, "" ]).count} space memories to the memories table"
  end

  def down
    # This migration is destructive in reverse - the original space.memory data
    # was not deleted. However, we should remove the migrated memories
    # to avoid duplicates if re-running the migration
    Memory.where("metadata->>'migrated_from_space_memory' = 'true'").destroy_all

    puts "Removed migrated summary memories"
  end
end
